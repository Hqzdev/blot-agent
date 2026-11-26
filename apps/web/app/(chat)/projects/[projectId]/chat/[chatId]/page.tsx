import { auth } from '@/app/(auth)/auth';
import { ProjectChatShell } from '@/components/projects/project-chat-shell';
import { DEFAULT_CHAT_MODEL } from '@/lib/ai/models';
import { toUIMessages } from '@/lib/chat/to-ui-messages';
import { getMessagesByChatId } from '@/lib/db/queries';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { cookies } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import { z } from 'zod';

export default async function Page({
  params,
}: {
  params: Promise<{ chatId: string; projectId: string }>;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    redirect('/login');
  }
  const { chatId, projectId } = await params;
  if (
    !z.string().uuid().safeParse(chatId).success ||
    !z.string().uuid().safeParse(projectId).success
  ) {
    notFound();
  }
  const gateway = getConversationGateway();
  try {
    const [project, chat] = await Promise.all([
      gateway.getProject(session.user.id, projectId),
      gateway.getChat(session.user.id, chatId),
    ]);
    if (!project || !chat || chat.projectId !== projectId) {
      notFound();
    }
  } catch {
    notFound();
  }
  const [cookieStore, messages] = await Promise.all([
    cookies(),
    getMessagesByChatId({
      id: chatId,
      userId: session.user.id,
    }),
  ]);
  const selectedChatModel =
    cookieStore.get('chat-model')?.value ?? DEFAULT_CHAT_MODEL;
  return (
    <ProjectChatShell
      chatId={chatId}
      projectId={projectId}
      selectedChatModel={selectedChatModel}
      initialMessages={toUIMessages(messages)}
      nickname={session.user.nickname}
    />
  );
}
