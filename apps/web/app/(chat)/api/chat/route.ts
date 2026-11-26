import {QuotaExceeded} from '@/lib/billing/usage';
import { auth } from '@/app/(auth)/auth';
import { systemPrompt } from '@/lib/ai/prompts';
import { myProvider } from '@/lib/ai/providers';
import { buildSkillCatalogPrompt } from '@/lib/ai/skills/skill-catalog-prompt';
import {
  redactLoadedSkillInstructions,
  stripLoadedSkillsFromMessages,
} from '@/lib/ai/skills/skill-message-sanitizer';
import { createDocument } from '@/lib/ai/tools/create-document';
import { getWeather } from '@/lib/ai/tools/get-weather';
import { SkillLoader } from '@/lib/ai/tools/load-skill';
import { requestSuggestions } from '@/lib/ai/tools/request-suggestions';
import { updateDocument } from '@/lib/ai/tools/update-document';
import { isProductionEnvironment } from '@/lib/constants';
import {
  deleteChatById,
  getChatById,
  saveChat,
  saveMessages,
} from '@/lib/db/queries';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getIdentityGateway } from '@/lib/services/identity-gateway';
import { getSkillGateway } from '@/lib/services/skill-gateway';
import { createWebRateLimitStore } from '@/lib/services/web-rate-limit-store';
import {
  generateUUID,
  getMostRecentUserMessage,
  getTrailingMessageId,
} from '@/lib/utils';
import { customizationSchema } from '@teya/contracts';
import { RateLimiter } from '@teya/platform';
import {
  ConversationForbiddenError,
  ConversationNotFoundError,
} from '@teya/service-conversation';
import type { Message, UIMessage } from 'ai';
import {
  appendResponseMessages,
  createDataStreamResponse,
  smoothStream,
  streamText,
} from 'ai';
import { z } from 'zod';
import { generateTitleFromUserMessage } from '../../actions';

export const maxDuration = 300;

const chatRequestSchema = z.object({
  id: z.string().uuid(),
  projectId: z.string().uuid().optional(),
  messages: z
    .array(
      z
        .object({
          content: z.string().max(500_000).optional(),
          experimental_attachments: z.array(z.unknown()).max(20).optional(),
          id: z.string().min(1).max(128),
          parts: z.array(z.unknown()).max(200).optional(),
          role: z.enum(['system', 'user', 'assistant', 'data']),
        })
        .passthrough(),
    )
    .min(1)
    .max(200),
  selectedChatModel: z.enum(['chat-model', 'chat-model-reasoning']),
});

let rateLimiter: RateLimiter | undefined;

function getRateLimiter(): RateLimiter {
  rateLimiter ??= new RateLimiter(
    createWebRateLimitStore(),
    80,
    10_800,
    'chat',
  );
  return rateLimiter;
}

function extractMessageText(message: Message): string {
  return typeof message.content === 'string' ? message.content : '';
}

function normalizeMessageParts(message: Message): unknown[] {
  if (message.parts && message.parts.length > 0) {
    return message.parts;
  }

  return [{ type: 'text' as const, text: extractMessageText(message) }];
}

async function createChatIfNeeded(
  id: string,
  userId: string,
  userMessage: UIMessage,
  projectId?: string,
) {
  const chat = await getChatById({ id, userId });
  if (chat) {
    if (chat.projectId !== (projectId ?? null)) {
      throw new ProjectChatMismatchError();
    }
    return;
  }

  let title: string;
  try {
    title = await generateTitleFromUserMessage({ message: userMessage });
  } catch {
    title = extractMessageText(userMessage).slice(0, 60).trim() || 'New Chat';
  }
  await saveChat({ id, projectId, userId, title });
}

class ProjectChatMismatchError extends Error {}

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return new Response('Unauthorized', { status: 401 });
  }

  try {
    const parsedRequest = chatRequestSchema.safeParse(await request.json());
    if (!parsedRequest.success) {
      return new Response('Invalid request', { status: 400 });
    }

    const { id, projectId, selectedChatModel } = parsedRequest.data;
    const messages = parsedRequest.data.messages as UIMessage[];
    const rateLimit = await getRateLimiter().consume(userId);
    if (!rateLimit.allowed) {
      const retryAfter = Math.max(
        1,
        Math.ceil((rateLimit.resetAt.getTime() - Date.now()) / 1000),
      );
      return new Response('Rate limit exceeded', {
        headers: { 'retry-after': retryAfter.toString() },
        status: 429,
      });
    }

    const userMessage = getMostRecentUserMessage(messages);
    if (!userMessage) {
      return new Response('No user message found', { status: 400 });
    }

    await createChatIfNeeded(id, userId, userMessage, projectId);
    const user = await getIdentityGateway().getUser(userId);
    const parsedCustomization = customizationSchema.safeParse(
      user.customization,
    );
    const customization = parsedCustomization.success
      ? parsedCustomization.data
      : null;
    await saveMessages({
      messages: [
        {
          chatId: id,
          id: userMessage.id,
          role: 'user',
          parts: normalizeMessageParts(userMessage),
          attachments: userMessage.experimental_attachments ?? [],
          createdAt: new Date(),
        },
      ],
      userId,
    });
    const projectContext = projectId
      ? await getConversationGateway().getProjectContext(userId, projectId, id)
      : '';
    const skillGateway = getSkillGateway();
    const installedSkills = await skillGateway
      .getInstalledSkillSummaries(userId)
      .catch((error) => {
        console.error('Installed skills could not be loaded', error);
        return [];
      });
    const skillCatalog = buildSkillCatalogPrompt(installedSkills);
    const skillLoader =
      installedSkills.length > 0
        ? new SkillLoader(installedSkills, userId, skillGateway)
        : null;
    const modelMessages = stripLoadedSkillsFromMessages(messages);

    return createDataStreamResponse({
      execute: async (dataStream) => {
        const system = systemPrompt({
          customization,
          projectContext,
          selectedChatModel,
          skillCatalog,
        });
        const loadSkill = skillLoader?.createTool();
        const tools = {
          getWeather,
          createDocument: createDocument({ session, dataStream }),
          updateDocument: updateDocument({ session, dataStream }),
          requestSuggestions: requestSuggestions({ session, dataStream }),
          ...(loadSkill ? { loadSkill } : {}),
        };
        const activeTools =
          selectedChatModel === 'chat-model-reasoning'
            ? loadSkill
              ? ['loadSkill' as const]
              : []
            : [
                'getWeather' as const,
                'createDocument' as const,
                'updateDocument' as const,
                'requestSuggestions' as const,
                ...(loadSkill ? (['loadSkill'] as const) : []),
              ];
        const result = streamText({
          model: myProvider.languageModel(selectedChatModel),
          system,
          messages: modelMessages,
          maxSteps: 5,
          experimental_activeTools: activeTools,
          experimental_transform: smoothStream({ chunking: 'word' }),
          experimental_generateMessageId: generateUUID,
          tools,
          onFinish: async ({ response, finishReason }) => {
            if (finishReason !== 'stop' && finishReason !== 'tool-calls') {
              return;
            }

            const assistantMessages = response.messages.filter(
              (message) => message.role === 'assistant',
            );
            const assistantId = getTrailingMessageId({
              messages: assistantMessages,
            });
            if (!assistantId) {
              return;
            }

            const [, assistantMessage] = appendResponseMessages({
              messages: [userMessage],
              responseMessages: response.messages,
            });
            if (!assistantMessage) {
              return;
            }

            await saveMessages({
              messages: [
                {
                  id: assistantId,
                  chatId: id,
                  role: 'assistant',
                  parts: redactLoadedSkillInstructions(
                    normalizeMessageParts(assistantMessage),
                  ),
                  attachments: assistantMessage.experimental_attachments ?? [],
                  createdAt: new Date(),
                },
              ],
              userId,
            });
          },
          experimental_telemetry: {
            isEnabled: isProductionEnvironment,
            functionId: 'stream-text',
          },
        });

        result.consumeStream();
        result.mergeIntoDataStream(dataStream, { sendReasoning: true });
      },
      onError: (error) => {
        if(error instanceof QuotaExceeded) return error.message;
        console.error('Chat response generation failed', error);
        return 'Произошла ошибка при генерации ответа. Пожалуйста, попробуйте ещё раз.';
      },
    });
  } catch (error) {
    if (error instanceof ProjectChatMismatchError) {
      return new Response('Chat does not belong to this project', {
        status: 403,
      });
    }
    if (error instanceof ConversationForbiddenError) {
      return new Response(error.message, { status: 403 });
    }
    if (error instanceof ConversationNotFoundError) {
      return new Response(error.message, { status: 404 });
    }
    console.error('Chat request failed', error);
    return new Response('Unable to process chat request', { status: 500 });
  }
}

export async function DELETE(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return new Response('Unauthorized', { status: 401 });
  }

  const id = new URL(request.url).searchParams.get('id');
  if (!id || !z.string().uuid().safeParse(id).success) {
    return new Response('Not Found', { status: 404 });
  }

  try {
    const chat = await getChatById({ id, userId });
    if (!chat) {
      return new Response('Chat not found', { status: 404 });
    }

    await deleteChatById({ id, userId });
    return new Response('Chat deleted', { status: 200 });
  } catch (error) {
    console.error('Chat deletion failed', error);
    return new Response('Unable to delete chat', { status: 500 });
  }
}
