'use client';

import { ChatHeader } from '@/components/chat-header';
import { useArtifactSelector } from '@/hooks/use-artifact';
import type { Vote } from '@/lib/db/schema';
import { fetcher, generateUUID } from '@/lib/utils';
import { webPath } from '@/lib/web-path';
import { useChat } from '@ai-sdk/react';
import dynamic from 'next/dynamic';
import { Suspense, memo, useEffect, useRef, useState } from 'react';
import { toast } from 'sonner';
import useSWR, { useSWRConfig } from 'swr';
import { Messages } from './messages';
import { VisibilityType } from './visibility-selector';

const Artifact = dynamic(
  () => import('./artifact').then((mod) => ({ default: mod.Artifact })),
  {
    ssr: false,
  },
);

const MultimodalInput = dynamic(
  () =>
    import('@/components/multimodal-input').then((mod) => ({
      default: mod.MultimodalInput,
    })),
  {
    ssr: false,
    loading: () => (
      <div className="absolute left-1/2 top-1/2 h-[60px] w-[calc(100%-1.5rem)] max-w-[768px] -translate-x-1/2 -translate-y-[30px] rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] shadow-[0_8px_30px_var(--chat-shadow)]" />
    ),
  },
);

export const Chat = memo(function Chat({
  id,
  initialMessages,
  selectedChatModel,
  selectedVisibilityType,
  isReadonly,
  nickname,
  projectId,
  chatPath,
  draftStorageKey,
}: {
  id: string;
  initialMessages: Array<import('ai').UIMessage>;
  selectedChatModel: string;
  selectedVisibilityType: VisibilityType;
  isReadonly: boolean;
  nickname?: string;
  projectId?: string;
  chatPath?: string;
  draftStorageKey?: string;
}) {
  const { mutate } = useSWRConfig();
  const [activeChatModel, setActiveChatModel] = useState(selectedChatModel);
  const hasSubmittedDraft = useRef(false);
  const writeBarrier = useRef(0);

  const {
    messages,
    setMessages,
    handleSubmit,
    input,
    setInput,
    append,
    status,
    stop,
    reload,
  } = useChat({
    api: '/app/api/chat',
    id,
    body: { id, projectId, selectedChatModel: activeChatModel },
    initialMessages,
    experimental_throttle: 100,
    sendExtraMessageFields: true,
    generateId: generateUUID,
    onFinish: () => {
      writeBarrier.current = Date.now();
      mutate('/app/api/history');
    },
    onError: (error) => {
      console.error('Error in useChat:', error);
      toast.error(
        `An error occurred: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
    },
  });

  const { data: synchronized } = useSWR(
    !isReadonly && status === 'ready'
      ? `/app/api/conversations/${id}/messages`
      : null,
    async (url: string) => {
      const requestedAt = Date.now();
      const rows = await fetcher(url);
      return {
        requestedAt,
        messages: rows.map((row: import('@/lib/db/schema').DBMessage) => ({
          id: row.id,
          role: row.role,
          parts: row.parts,
          content: '',
          createdAt: row.createdAt,
          experimental_attachments: row.attachments ?? [],
        })) as import('ai').UIMessage[],
      };
    },
    {
      refreshInterval: 5000,
      revalidateOnFocus: true,
      shouldRetryOnError: false,
    },
  );
  useEffect(() => {
    if (status !== 'ready') {
      writeBarrier.current = Date.now();
      return;
    }
    if (!synchronized || synchronized.requestedAt <= writeBarrier.current)
      return;
    if (JSON.stringify(messages) !== JSON.stringify(synchronized.messages))
      setMessages(synchronized.messages);
  }, [synchronized, status, messages, setMessages]);

  useEffect(() => {
    if (!draftStorageKey || hasSubmittedDraft.current) {
      return;
    }
    const draft = sessionStorage.getItem(draftStorageKey)?.trim();
    if (!draft) {
      return;
    }
    hasSubmittedDraft.current = true;
    sessionStorage.removeItem(draftStorageKey);
    window.history.replaceState({}, '', webPath(chatPath ?? `/chat/${id}`));
    append({ role: 'user', content: draft });
  }, [append, chatPath, draftStorageKey, id]);

  const { data: votes } = useSWR<Array<Vote>>(
    messages.length >= 2 ? `/app/api/vote?chatId=${id}` : null,
    fetcher,
  );

  const [attachments, setAttachments] = useState<
    Array<import('ai').Attachment>
  >([]);
  const isArtifactVisible = useArtifactSelector((state) => state.isVisible);

  return (
    <>
      <div
        key="chat-main"
        className="relative flex h-svh min-w-0 flex-col overflow-hidden bg-[var(--chat-paper)] pt-[52px] text-[var(--chat-ink)]"
      >
        <ChatHeader
          selectedModelId={activeChatModel}
          onModelChange={setActiveChatModel}
        />
        <div className="flex min-h-0 flex-1 flex-col pb-28">
          <Suspense
            fallback={
              <div className="flex flex-1 items-center justify-center text-sm text-[var(--chat-hollow)]">
                Loading messages...
              </div>
            }
          >
            <Messages
              chatId={id}
              status={status}
              votes={votes}
              messages={messages}
              setMessages={setMessages}
              reload={reload}
              isReadonly={isReadonly}
              isArtifactVisible={isArtifactVisible}
              selectedChatModel={activeChatModel}
              nickname={nickname}
            />
          </Suspense>
        </div>
        {!isReadonly && !isArtifactVisible && (
          <Suspense fallback={<div className="h-20" />}>
            <MultimodalInput
              chatId={id}
              input={input}
              setInput={setInput}
              status={status}
              stop={stop}
              attachments={attachments}
              setAttachments={setAttachments}
              messages={messages}
              setMessages={setMessages}
              append={append}
              chatPath={chatPath}
            />
          </Suspense>
        )}
      </div>
      {isArtifactVisible && (
        <Suspense fallback={null}>
          <Artifact
            key="chat-artifact"
            chatId={id}
            input={input}
            setInput={setInput}
            handleSubmit={handleSubmit}
            status={status}
            stop={stop}
            attachments={attachments}
            setAttachments={setAttachments}
            append={append}
            messages={messages}
            setMessages={setMessages}
            reload={reload}
            votes={votes}
            isReadonly={isReadonly}
          />
        </Suspense>
      )}
    </>
  );
});
