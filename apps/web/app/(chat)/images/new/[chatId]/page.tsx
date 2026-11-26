import { auth } from '@/app/(auth)/auth';
import { Chat } from '@/components/chat';
import { DataStreamHandler } from '@/components/data-stream-handler';
import { DEFAULT_CHAT_MODEL } from '@/lib/ai/models';
import { cookies } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import { z } from 'zod';

export default async function Page({
  params,
}: {
  params: Promise<{ chatId: string }>;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    redirect('/login');
  }
  const { chatId } = await params;
  if (!z.string().uuid().safeParse(chatId).success) {
    notFound();
  }
  const cookieStore = await cookies();
  const selectedChatModel =
    cookieStore.get('chat-model')?.value ?? DEFAULT_CHAT_MODEL;
  const chatPath = `/chat/${chatId}`;
  return (
    <>
      <Chat
        key={chatId}
        id={chatId}
        initialMessages={[]}
        selectedChatModel={selectedChatModel}
        selectedVisibilityType="private"
        isReadonly={false}
        nickname={session.user.nickname}
        chatPath={chatPath}
        draftStorageKey={`teya:image-draft:${chatId}`}
      />
      <DataStreamHandler id={chatId} />
    </>
  );
}
