'use server';

import type { Message } from 'ai';
import { generateText } from 'ai';
import { cookies } from 'next/headers';

import { auth } from '@/app/(auth)/auth';
import type { VisibilityType } from '@/components/visibility-selector';
import { myProvider } from '@/lib/ai/providers';
import {
  deleteMessagesByChatIdAfterTimestamp,
  getMessageById,
  updateChatVisiblityById,
} from '@/lib/db/queries';

const allowedModels = new Set(['chat-model', 'chat-model-reasoning']);

export async function saveChatModelAsCookie(model: string) {
  if (!allowedModels.has(model)) {
    throw new Error('Invalid chat model');
  }
  const cookieStore = await cookies();
  cookieStore.set('chat-model', model, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
  });
}

export async function generateTitleFromUserMessage({
  message,
}: {
  message: Message;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    throw new Error('Unauthorized');
  }
  const messageText = getMessageText(message).trim();
  if (!messageText) {
    return 'New Chat';
  }

  try {
    const result = await generateText({
      model: myProvider.languageModel('title-model'),
      prompt: messageText,
      system:
        'Generate a concise title under 80 characters that summarizes the user message. Do not use quotes or colons.',
    });
    if (result.text.trim()) {
      return result.text.trim().slice(0, 80);
    }
  } catch {
    return messageText.slice(0, 60);
  }

  return messageText.slice(0, 60);
}

export async function deleteTrailingMessages({ id }: { id: string }) {
  const userId = await requireUserId();
  const [message] = await getMessageById({ id, userId });
  await deleteMessagesByChatIdAfterTimestamp({
    chatId: message.chatId,
    timestamp: message.createdAt,
    userId,
  });
}

export async function updateChatVisibility({
  chatId,
  visibility,
}: {
  chatId: string;
  visibility: VisibilityType;
}) {
  const userId = await requireUserId();
  await updateChatVisiblityById({ chatId, userId, visibility });
}

function getMessageText(message: Message): string {
  return typeof message.content === 'string' ? message.content : '';
}

async function requireUserId(): Promise<string> {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    throw new Error('Unauthorized');
  }
  return userId;
}
