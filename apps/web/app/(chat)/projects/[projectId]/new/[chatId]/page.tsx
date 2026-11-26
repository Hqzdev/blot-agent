import { auth } from '@/app/(auth)/auth';
import { ProjectChatShell } from '@/components/projects/project-chat-shell';
import { DEFAULT_CHAT_MODEL } from '@/lib/ai/models';
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
  try {
    await getConversationGateway().getProject(session.user.id, projectId);
  } catch {
    notFound();
  }
  const cookieStore = await cookies();
  const selectedChatModel =
    cookieStore.get('chat-model')?.value ?? DEFAULT_CHAT_MODEL;
  return (
    <ProjectChatShell
      chatId={chatId}
      projectId={projectId}
      selectedChatModel={selectedChatModel}
      initialMessages={[]}
      nickname={session.user.nickname}
      draftStorageKey={`teya:project-draft:${chatId}`}
    />
  );
}
