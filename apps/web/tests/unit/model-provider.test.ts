import assert from 'node:assert/strict';
import test from 'node:test';

import {
  GIGACHAT_REASONING_TAG,
  TeyaModelProviderFactory,
} from '@teya/service-ai-gateway';
import { generateText } from 'ai';

function createCompletionResponse(content: string): Response {
  return Response.json({
    choices: [
      {
        finish_reason: 'stop',
        index: 0,
        message: {
          content,
          role: 'assistant',
        },
      },
    ],
    created: 1_800_000_000,
    id: 'completion-id',
    model: 'teya',
    object: 'chat.completion',
    usage: {
      completion_tokens: 4,
      prompt_tokens: 3,
      total_tokens: 7,
    },
  });
}

test('Teya Max enables GigaChat reasoning and exposes it separately', async () => {
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> | undefined;
  globalThis.fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body));
    return createCompletionResponse(
      `Проверяю решение</${GIGACHAT_REASONING_TAG}>Готовый ответ`,
    );
  };

  try {
    const provider = new TeyaModelProviderFactory().create({
      AI_GATEWAY_URL: 'https://gateway.example',
      INTERNAL_SERVICE_SECRET: 'internal-secret',
      NODE_ENV: 'test',
    } as NodeJS.ProcessEnv);
    const result = await generateText({
      model: provider.languageModel('chat-model-reasoning'),
      prompt: 'Реши задачу',
    });

    assert.equal(requestBody?.reasoning_effort, 'medium');
    assert.equal(result.reasoning, 'Проверяю решение');
    assert.equal(result.text, 'Готовый ответ');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('standard Teya model does not enable GigaChat reasoning', async () => {
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> | undefined;
  globalThis.fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body));
    return createCompletionResponse('Обычный ответ');
  };

  try {
    const provider = new TeyaModelProviderFactory().create({
      AI_GATEWAY_URL: 'https://gateway.example',
      INTERNAL_SERVICE_SECRET: 'internal-secret',
      NODE_ENV: 'test',
    } as NodeJS.ProcessEnv);
    const result = await generateText({
      model: provider.languageModel('chat-model'),
      prompt: 'Ответь на вопрос',
    });

    assert.equal(requestBody?.reasoning_effort, undefined);
    assert.equal(result.reasoning, undefined);
    assert.equal(result.text, 'Обычный ответ');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
