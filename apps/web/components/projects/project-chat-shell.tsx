import { Chat } from '@/components/chat';
import { DataStreamHandler } from '@/components/data-stream-handler';
import type { UIMessage } from 'ai';

export function ProjectChatShell({
  chatId,
  projectId,
  selectedChatModel,
  initialMessages,
  nickname,
  draftStorageKey,
}: {
  chatId: string;
  projectId: string;
  selectedChatModel: string;
  initialMessages: UIMessage[];
  nickname?: string;
  draftStorageKey?: string;
}) {
  const chatPath = `/projects/${projectId}/chat/${chatId}`;
  return (
    <>
      <Chat
        key={chatId}
        id={chatId}
        initialMessages={initialMessages}
        selectedChatModel={selectedChatModel}
        selectedVisibilityType="private"
        isReadonly={false}
        nickname={nickname}
        projectId={projectId}
        chatPath={chatPath}
        draftStorageKey={draftStorageKey}
      />
      <DataStreamHandler id={chatId} />
    </>
  );
}
