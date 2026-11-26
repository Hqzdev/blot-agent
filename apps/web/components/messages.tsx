import type { Vote } from '@/lib/db/schema';
import type { UseChatHelpers } from '@ai-sdk/react';
import type { UIMessage } from 'ai';
import equal from 'fast-deep-equal';
import { memo, useEffect } from 'react';
import { PreviewMessage, ThinkingMessage } from './message';
import { Overview } from './overview';
import { useScrollToBottom } from './use-scroll-to-bottom';

interface MessagesProps {
  chatId: string;
  status: UseChatHelpers['status'];
  votes: Array<Vote> | undefined;
  messages: Array<UIMessage>;
  setMessages: UseChatHelpers['setMessages'];
  reload: UseChatHelpers['reload'];
  isReadonly: boolean;
  isArtifactVisible: boolean;
  selectedChatModel: string;
  nickname?: string;
}

function PureMessages({
  chatId,
  status,
  votes,
  messages,
  setMessages,
  reload,
  isReadonly,
  selectedChatModel,
  nickname,
}: MessagesProps) {
  const {
    containerRef: messagesContainerRef,
    endRef: messagesEndRef,
    scrollToBottom,
  } = useScrollToBottom();

  useEffect(() => {
    scrollToBottom('auto');
  }, [messages.length, status]);

  useEffect(() => {
    if (status === 'streaming' && messages.length > 0) {
      scrollToBottom('smooth');
    }
  }, [status, messages[messages.length - 1]?.content]);

  return (
    <div
      ref={messagesContainerRef}
      className="flex min-w-0 flex-1 flex-col gap-6 overflow-y-auto overscroll-contain pt-5"
    >
      {messages.length === 0 && (
        <Overview chatId={chatId} nickname={nickname} />
      )}
      {messages.map((message, index) => (
        <div key={message.id || `message-${index}`}>
          <PreviewMessage
            chatId={chatId}
            message={message}
            isLoading={status === 'streaming' && messages.length - 1 === index}
            vote={
              votes
                ? votes.find((vote) => vote.messageId === message.id)
                : undefined
            }
            setMessages={setMessages}
            reload={reload}
            isReadonly={isReadonly}
            selectedChatModel={selectedChatModel}
          />
        </div>
      ))}
      {status === 'submitted' &&
        messages.length > 0 &&
        messages[messages.length - 1].role === 'user' && <ThinkingMessage />}
      <div ref={messagesEndRef} className="min-h-6 min-w-6 shrink-0" />
    </div>
  );
}

export const Messages = memo(PureMessages, (prevProps, nextProps) => {
  if (prevProps.isArtifactVisible && nextProps.isArtifactVisible) return true;

  if (prevProps.status !== nextProps.status) return false;
  if (prevProps.status && nextProps.status) return false;
  if (prevProps.messages.length !== nextProps.messages.length) return false;
  if (!equal(prevProps.messages, nextProps.messages)) return false;
  if (!equal(prevProps.votes, nextProps.votes)) return false;
  if (prevProps.selectedChatModel !== nextProps.selectedChatModel) return false;

  return true;
});
