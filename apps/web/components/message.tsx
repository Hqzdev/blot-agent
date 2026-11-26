'use client';

import type { Vote } from '@/lib/db/schema';
import type { UIMessage } from 'ai';
import cx from 'classnames';
import dynamic from 'next/dynamic';
import { memo, useState } from 'react';
import { DocumentToolCall, DocumentToolResult } from './document';
import { PencilEditIcon } from './icons';

const Markdown = dynamic(
  () => import('./markdown').then((mod) => ({ default: mod.Markdown })),
  {
    ssr: false,
    loading: () => (
      <div className="h-20 animate-pulse rounded-[10px] bg-black/5" />
    ),
  },
);
import { cn } from '@/lib/utils';
import type { UseChatHelpers } from '@ai-sdk/react';
import equal from 'fast-deep-equal';
import { DocumentPreview } from './document-preview';
import { MessageActions } from './message-actions';
import { MessageEditor } from './message-editor';
import { MessageReasoning } from './message-reasoning';
import { PreviewAttachment } from './preview-attachment';
import { SkillUsage } from './skill-usage';
import { Button } from './ui/button';
import { Tooltip, TooltipContent, TooltipTrigger } from './ui/tooltip';
import { Weather } from './weather';

const PurePreviewMessage = ({
  chatId,
  message,
  vote,
  isLoading,
  setMessages,
  reload,
  isReadonly,
  selectedChatModel,
}: {
  chatId: string;
  message: UIMessage;
  vote: Vote | undefined;
  isLoading: boolean;
  setMessages: UseChatHelpers['setMessages'];
  reload: UseChatHelpers['reload'];
  isReadonly: boolean;
  selectedChatModel?: string;
}) => {
  const [mode, setMode] = useState<'view' | 'edit'>('view');
  const [copied, setCopied] = useState(false);

  return (
    <div
      data-testid={`message-${message.role}`}
      className="group/message mx-auto w-full max-w-[768px] px-4"
      data-role={message.role}
    >
      <div
        className={cn('flex w-full', {
          'justify-end': message.role === 'user' && mode !== 'edit',
        })}
      >
        <div
          className={cn('flex min-w-0 flex-col gap-3', {
            'w-full': message.role === 'assistant' || mode === 'edit',
            'max-w-[88%] items-end sm:max-w-[80%]':
              message.role === 'user' && mode !== 'edit',
          })}
        >
          {message.experimental_attachments && (
            <div
              data-testid={'message-attachments'}
              className="flex flex-row flex-wrap justify-end gap-2"
            >
              {message.experimental_attachments.map((attachment) => (
                <PreviewAttachment
                  key={attachment.url}
                  attachment={attachment}
                />
              ))}
            </div>
          )}

          {message.parts?.map((part, index) => {
            const { type } = part;
            const key = `message-${message.id}-part-${index}`;

            if (type === 'reasoning') {
              return (
                <MessageReasoning
                  key={key}
                  isLoading={isLoading}
                  reasoning={part.reasoning}
                />
              );
            }

            if (type === 'text') {
              if (mode === 'view') {
                return (
                  <div key={key} className="flex flex-row gap-2 items-start">
                    {message.role === 'user' && !isReadonly && (
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            data-testid="message-edit-button"
                            variant="ghost"
                            className="h-8 w-8 shrink-0 rounded-[10px] p-0 text-[var(--chat-hollow)] opacity-0 shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] group-hover/message:opacity-100"
                            onClick={() => {
                              setMode('edit');
                            }}
                          >
                            <PencilEditIcon />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>Edit message</TooltipContent>
                      </Tooltip>
                    )}

                    <div
                      data-testid="message-content"
                      className={cn('min-w-0 text-base', {
                        'w-full leading-7 text-[var(--chat-ink)]':
                          message.role === 'assistant',
                        'rounded-2xl bg-[var(--chat-hover)] px-4 py-2.5 leading-6 text-[var(--chat-ink)]':
                          message.role === 'user',
                      })}
                    >
                      <Markdown>{part.text}</Markdown>
                    </div>
                  </div>
                );
              }

              if (mode === 'edit') {
                return (
                  <div key={key} className="flex flex-row gap-2 items-start">
                    <div className="size-8" />

                    <MessageEditor
                      key={message.id}
                      message={message}
                      setMode={setMode}
                      setMessages={setMessages}
                      reload={reload}
                    />
                  </div>
                );
              }
            }

            if (type === 'tool-invocation') {
              const { toolInvocation } = part;
              const { toolName, toolCallId, state } = toolInvocation;

              if (state === 'call') {
                const { args } = toolInvocation;

                return (
                  <div
                    key={toolCallId}
                    className={cx({
                      skeleton: ['getWeather'].includes(toolName),
                    })}
                  >
                    {toolName === 'getWeather' ? (
                      <Weather />
                    ) : toolName === 'createDocument' ? (
                      <DocumentPreview isReadonly={isReadonly} args={args} />
                    ) : toolName === 'updateDocument' ? (
                      <DocumentToolCall
                        type="update"
                        args={args}
                        isReadonly={isReadonly}
                      />
                    ) : toolName === 'requestSuggestions' ? (
                      <DocumentToolCall
                        type="request-suggestions"
                        args={args}
                        isReadonly={isReadonly}
                      />
                    ) : toolName === 'loadSkill' ? (
                      <SkillUsage />
                    ) : null}
                  </div>
                );
              }

              if (state === 'result') {
                const { result } = toolInvocation;

                return (
                  <div key={toolCallId}>
                    {toolName === 'getWeather' ? (
                      <Weather weatherAtLocation={result} />
                    ) : toolName === 'createDocument' ? (
                      <DocumentPreview
                        isReadonly={isReadonly}
                        result={result}
                      />
                    ) : toolName === 'updateDocument' ? (
                      <DocumentToolResult
                        type="update"
                        result={result}
                        isReadonly={isReadonly}
                      />
                    ) : toolName === 'requestSuggestions' ? (
                      <DocumentToolResult
                        type="request-suggestions"
                        result={result}
                        isReadonly={isReadonly}
                      />
                    ) : toolName === 'loadSkill' ? (
                      <SkillUsage result={result} />
                    ) : (
                      <pre>{JSON.stringify(result, null, 2)}</pre>
                    )}
                  </div>
                );
              }
            }
          })}

          {!isReadonly && (
            <MessageActions
              key={`action-${message.id}`}
              chatId={chatId}
              message={message}
              vote={vote}
              isLoading={isLoading}
              copied={copied}
              setCopied={setCopied}
            />
          )}
        </div>
      </div>
    </div>
  );
};

export const PreviewMessage = memo(
  PurePreviewMessage,
  (prevProps, nextProps) => {
    if (prevProps.isLoading !== nextProps.isLoading) return false;
    if (prevProps.message.id !== nextProps.message.id) return false;
    if (!equal(prevProps.message.parts, nextProps.message.parts)) return false;
    if (!equal(prevProps.vote, nextProps.vote)) return false;
    if (prevProps.selectedChatModel !== nextProps.selectedChatModel)
      return false;
    return true;
  },
);

export const ThinkingMessage = memo(() => {
  return (
    <div
      data-testid="message-assistant-loading"
      className="mx-auto w-full max-w-[768px] px-4"
      data-role="assistant"
    >
      <div className="flex items-center gap-2 text-sm text-[var(--chat-hollow)]">
        <span className="size-1.5 animate-pulse rounded-full bg-[var(--chat-hollow)]" />
        <span>Thinking</span>
      </div>
    </div>
  );
});
ThinkingMessage.displayName = 'ThinkingMessage';
