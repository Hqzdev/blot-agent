import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseConnectionProvider } from '@teya/database';
import { TeyaModelProviderFactory } from '@teya/service-ai-gateway';
import {
  ConversationForbiddenError,
  ConversationService,
  PostgresConversationRepository,
} from '@teya/service-conversation';
import { generateText } from 'ai';
import { PostgresRateLimitStore } from '../lib/services/web-rate-limit-store';
import { verifySharedChatSync } from '../packages/chat-sync/src/verification.mjs';

const database = new DatabaseConnectionProvider().get();
const owner = randomUUID();
const chat = randomUUID();
const rateKey = `release-check:${randomUUID()}`;
const repository = new PostgresConversationRepository();
const service = new ConversationService(repository);
let stage = 'schema';

try {
  const tables = await database.client.unsafe(
    "SELECT to_regclass('public.blot_accounts') AS accounts, to_regclass('conversation.chats') AS chats",
  );
  assert.ok(
    tables[0].accounts && tables[0].chats,
    'Common accounts and web chat tables share this database',
  );
  stage = 'synchronization';
  await verifySharedChatSync(database.client);
  stage = 'create-chat';
  await service.saveChat(owner, chat, 'Blot release verification');
  let answer = 'Persistence check';
  if (process.argv.includes('--model')) {
    stage = 'model';
    const model = new TeyaModelProviderFactory()
      .create(process.env)
      .languageModel('chat-model');
    const generated = await generateText({
      model,
      prompt: 'Reply with exactly OK.',
      maxTokens: 8,
      maxRetries: 0,
      abortSignal: AbortSignal.timeout(60_000),
    });
    assert.ok(generated.text.trim(), 'GigaChat returned a real answer');
    answer = generated.text;
  }
  stage = 'messages';
  await service.saveMessages(owner, [
    {
      id: randomUUID(),
      chatId: chat,
      role: 'user',
      createdAt: new Date(),
      parts: [{ type: 'text', text: 'Reply with exactly OK.' }],
      attachments: [],
    },
    {
      id: randomUUID(),
      chatId: chat,
      role: 'assistant',
      createdAt: new Date(),
      parts: [{ type: 'text', text: answer }],
      attachments: [],
    },
  ]);
  stage = 'history';
  const reloaded = new ConversationService(
    new PostgresConversationRepository(),
  );
  assert.ok((await reloaded.getChats(owner)).some((item) => item.id === chat));
  assert.equal((await reloaded.getMessages(owner, chat)).length, 2);
  await assert.rejects(
    reloaded.getChat(randomUUID(), chat),
    ConversationForbiddenError,
  );
  const rate = new PostgresRateLimitStore();
  stage = 'rate-limits';
  assert.equal((await rate.increment(rateKey, 60)).count, 1);
  assert.equal((await rate.increment(rateKey, 60)).count, 2);
  console.log(
    'Blot cloud verification passed: common PostgreSQL, saved messages, history reload, owner isolation, shared rate limits',
    process.argv.includes('--model') ? 'and live GigaChat' : '',
  );
} catch (error) {
  console.error(
    'Blot cloud verification failed',
    error instanceof Error ? error.name : 'unknown',
    {
      stage,
      message:
        error instanceof Error
          ? error.message
              .replaceAll(
                process.env.BLOT_GIGACHAT_AUTH_KEY || '__unset_key__',
                '[redacted]',
              )
              .replaceAll(
                process.env.GIGACHAT_AUTH_KEY || '__unset_other_key__',
                '[redacted]',
              )
              .slice(0, 240)
          : '',
    },
  );
  process.exitCode = 1;
} finally {
  await database.client.unsafe(
    'DELETE FROM conversation.chats WHERE id=$1 AND user_id=$2',
    [chat, owner],
  );
  await database.client.unsafe(
    'DELETE FROM blot_web.rate_limits WHERE key=$1',
    [rateKey],
  );
  await database.close();
}
