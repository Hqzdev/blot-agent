import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { useHotkeys } from '@/hooks/use-hotkeys';
import { useOS } from '@/hooks/use-os';
import { webPath } from '@/lib/web-path';
import {
  Add01Icon,
  AiBrain01Icon,
  ArrowUp01Icon,
  Attachment01Icon,
  AudioWave01Icon,
  ChartNoAxesCombinedIcon,
  Globe02Icon,
  StopIcon as HugeStopIcon,
  Image01Icon,
  Mic01Icon,
  PencilEdit01Icon,
} from '@hugeicons/core-free-icons';
import type { IconSvgElement } from '@hugeicons/react';
import type { Attachment, Message } from 'ai';
import { AnimatePresence, motion } from 'framer-motion';
import React from 'react';
import { memo, useCallback, useEffect, useRef, useState } from 'react';
import type { ChangeEvent, Dispatch, SetStateAction } from 'react';
import { toast } from 'sonner';
import { useLocalStorage, useWindowSize } from 'usehooks-ts';
import { HotkeyBadge } from './hotkey-badge';

import type { UseChatHelpers } from '@ai-sdk/react';
import equal from 'fast-deep-equal';
import { Markdown } from './markdown';
import { PreviewAttachment } from './preview-attachment';
import { SearchResults } from './search-results';
import { SearchResultsImageSection } from './search-results-image';
import { Button } from './ui/button';
import { RoundedIcon } from './ui/rounded-icon';
import { Textarea } from './ui/textarea';
import { VideoSearchResults } from './video-search-results';

interface SpeechRecognitionResultItem {
  transcript: string;
}

interface SpeechRecognitionResult {
  0: SpeechRecognitionResultItem;
}

interface SpeechRecognitionResultEvent extends Event {
  resultIndex: number;
  results: ArrayLike<SpeechRecognitionResult>;
}

interface SpeechRecognitionInstance {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  onresult: ((event: SpeechRecognitionResultEvent) => void) | null;
  start: () => void;
  stop: () => void;
}

type SpeechRecognitionConstructor = new () => SpeechRecognitionInstance;

type SpeechRecognitionWindow = Window & {
  SpeechRecognition?: SpeechRecognitionConstructor;
  webkitSpeechRecognition?: SpeechRecognitionConstructor;
};

const PROMPTS = {
  web: [
    'What is the latest news in technology?',
    'Find me a recipe for a healthy breakfast',
    "What's the weather like in Tokyo?",
    'How do I start learning Python?',
    'Best places to visit in Europe',
    'Explain quantum computing in simple terms',
    'What are the top movies this year?',
    'How to improve productivity at work?',
    'What is the stock price of Apple?',
    'Tips for remote work',
    'What is AI and how does it work?',
    'How to cook pasta al dente?',
    'What are the symptoms of flu?',
    'How to meditate effectively?',
    'What is the capital of Australia?',
    'How to save money on groceries?',
    'What is the best smartphone in 2024?',
    'How to learn a new language fast?',
    'What are the benefits of yoga?',
    'How to write a resume?',
  ],
};

function getRandomPrompts(arr: string[], n: number) {
  const shuffled = arr.slice().sort(() => 0.5 - Math.random());
  return shuffled.slice(0, n);
}

function SuggestedPrompts({
  mode,
  input,
  onSelect,
}: {
  mode: 'web' | null;
  input: string;
  onSelect: (prompt: string) => void;
}) {
  const [suggestions, setSuggestions] = useState<string[]>([]);
  useEffect(() => {
    if (mode && !input) {
      setSuggestions(getRandomPrompts(PROMPTS[mode], 4));
    } else {
      setSuggestions([]);
    }
  }, [mode, input]);

  if (suggestions.length === 0) return null;
  return (
    <AnimatePresence>
      <motion.div
        className="mb-1 flex flex-col rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] p-1"
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -24 }}
        transition={{ duration: 0.22, ease: 'easeOut' }}
      >
        {suggestions.map((prompt, i) => (
          <React.Fragment key={prompt}>
            <button
              type="button"
              className="group w-full cursor-pointer rounded-lg border-none px-3 py-2 text-left text-sm leading-5 text-[var(--chat-mid-ash)] transition-colors hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]"
              onClick={() => onSelect(prompt)}
            >
              {mode === 'web' && (
                <span className="mr-2 inline-flex items-center align-middle">
                  <RoundedIcon icon={ChartNoAxesCombinedIcon} size={16} />
                </span>
              )}
              {prompt}
            </button>
            {i !== suggestions.length - 1 && (
              <div className="mx-2 h-px bg-[var(--chat-hairline)]" />
            )}
          </React.Fragment>
        ))}
      </motion.div>
    </AnimatePresence>
  );
}

function PureMultimodalInput({
  chatId,
  input,
  setInput,
  status,
  stop,
  attachments,
  setAttachments,
  messages,
  setMessages,
  append,
  className,
  chatPath,
}: {
  chatId: string;
  input: UseChatHelpers['input'];
  setInput: UseChatHelpers['setInput'];
  status: UseChatHelpers['status'];
  stop: () => void;
  attachments: Array<Attachment>;
  setAttachments: Dispatch<SetStateAction<Array<Attachment>>>;
  messages: Array<Message>;
  setMessages: Dispatch<SetStateAction<Array<Message>>>;
  append: UseChatHelpers['append'];
  className?: string;
  chatPath?: string;
}) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { width } = useWindowSize();
  const [isJustifyMode, setIsJustifyMode] = useState(false);
  const [isDraggingFile, setIsDraggingFile] = useState(false);
  const [webSearchResults, setWebSearchResults] = useState<any>(null);
  const [webSearchLoading, setWebSearchLoading] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const speechRecognitionRef = useRef<SpeechRecognitionInstance | null>(null);
  const os = useOS();

  useHotkeys(
    { key: 'l', meta: true },
    (e) => {
      e.preventDefault();
      textareaRef.current?.focus();
    },
    { os },
  );

  useEffect(() => {
    if (textareaRef.current) {
      adjustHeight();
    }
  }, []);

  const adjustHeight = () => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight + 2}px`;
    }
  };

  const resetHeight = () => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = '58px';
    }
  };

  const [localStorageInput, setLocalStorageInput] = useLocalStorage(
    'input',
    '',
  );

  useEffect(() => {
    if (textareaRef.current) {
      const domValue = textareaRef.current.value;

      const finalValue = domValue || localStorageInput || '';
      setInput(finalValue);
      adjustHeight();
    }
  }, []);

  useEffect(() => {
    setLocalStorageInput(input);
  }, [input, setLocalStorageInput]);

  useEffect(() => {
    adjustHeight();
  }, [input]);

  const handleInput = (event: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(event.target.value);
    adjustHeight();
  };

  const focusInput = useCallback(() => {
    requestAnimationFrame(() => {
      textareaRef.current?.focus();
      adjustHeight();
    });
  }, []);

  const selectQuickAction = useCallback(
    (prompt: string, useWebSearch = false) => {
      setIsJustifyMode(useWebSearch);
      setInput(prompt);
      focusInput();
    },
    [focusInput, setInput],
  );

  const stopDictation = useCallback(() => {
    speechRecognitionRef.current?.stop();
    speechRecognitionRef.current = null;
    setIsListening(false);
  }, []);

  const toggleDictation = useCallback(() => {
    if (speechRecognitionRef.current) {
      stopDictation();
      return;
    }

    const speechWindow = window as SpeechRecognitionWindow;
    const Recognition =
      speechWindow.SpeechRecognition || speechWindow.webkitSpeechRecognition;

    if (!Recognition) {
      toast.error('Voice input is not supported in this browser');
      return;
    }

    const recognition = new Recognition();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = navigator.language || 'en-US';
    recognition.onresult = (event) => {
      const transcripts: string[] = [];

      for (
        let index = event.resultIndex;
        index < event.results.length;
        index++
      ) {
        transcripts.push(event.results[index][0].transcript);
      }

      const transcript = transcripts.join(' ').trim();
      if (transcript) {
        setInput((currentInput) =>
          currentInput.trim()
            ? `${currentInput.trimEnd()} ${transcript}`
            : transcript,
        );
        focusInput();
      }
    };
    recognition.onerror = () => {
      speechRecognitionRef.current = null;
      setIsListening(false);
      toast.error('Voice input stopped unexpectedly');
    };
    recognition.onend = () => {
      speechRecognitionRef.current = null;
      setIsListening(false);
    };
    speechRecognitionRef.current = recognition;
    recognition.start();
    setIsListening(true);
  }, [focusInput, setInput, stopDictation]);

  useEffect(() => stopDictation, [stopDictation]);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadQueue, setUploadQueue] = useState<Array<string>>([]);

  const submitForm = useCallback(async () => {
    if (!input.trim() && attachments.length === 0) {
      return;
    }

    window.history.replaceState({}, '', webPath(chatPath ?? `/chat/${chatId}`));

    const userPrompt = input.trim();
    if (isJustifyMode) {
      setWebSearchLoading(true);
      setWebSearchResults(null);
      try {
        const res = await fetch('/app/api/websearch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query: userPrompt }),
        });
        const data = await res.json();
        setWebSearchResults(data);
      } catch (e) {
        toast.error('Ошибка поиска в интернете');
      } finally {
        setWebSearchLoading(false);
      }
      setAttachments([]);
      setLocalStorageInput('');
      setInput('');
      resetHeight();
      if (width && width > 768) {
        textareaRef.current?.focus();
      }
      return;
    }

    append(
      { role: 'user', content: userPrompt },
      {
        experimental_attachments: attachments,
      },
    );
    setAttachments([]);
    setLocalStorageInput('');
    setInput('');
    resetHeight();
    if (width && width > 768) {
      textareaRef.current?.focus();
    }
  }, [
    attachments,
    append,
    setAttachments,
    setLocalStorageInput,
    width,
    chatPath,
    chatId,
    input,
    isJustifyMode,
    setInput,
  ]);

  const uploadFile = useCallback(async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch('/app/api/files/upload', {
        method: 'POST',
        body: formData,
      });

      if (response.ok) {
        const data = await response.json();
        const { url, name, contentType, libraryItemId } = data;

        return {
          url,
          name,
          contentType: contentType,
          libraryItemId,
        };
      }
      const { error } = await response.json();
      toast.error(error);
    } catch (error) {
      toast.error('Failed to upload file, please try again!');
    }
  }, []);

  const handleFileChange = useCallback(
    async (event: ChangeEvent<HTMLInputElement>) => {
      const files = Array.from(event.target.files || []);

      setUploadQueue(files.map((file) => file.name));

      try {
        const uploadPromises = files.map((file) => uploadFile(file));
        const uploadedAttachments = await Promise.all(uploadPromises);
        const successfullyUploadedAttachments = uploadedAttachments
          .filter((a) => a?.url)
          .filter((a) => typeof a?.name === 'string')
          .map((a) => a as Attachment);

        setAttachments((currentAttachments) => [
          ...currentAttachments,
          ...successfullyUploadedAttachments,
        ]);
      } catch (error) {
        console.error('Error uploading files!', error);
      } finally {
        setUploadQueue([]);
      }
    },
    [setAttachments, uploadFile],
  );

  useEffect(() => {
    const onDragEnter = (e: DragEvent) => {
      if (e.dataTransfer?.types?.includes('Files')) {
        setIsDraggingFile(true);
      }
    };
    const onDragLeave = (e: DragEvent) => {
      if (
        e.relatedTarget == null ||
        !(e.relatedTarget as HTMLElement)?.closest('body')
      ) {
        setIsDraggingFile(false);
      }
    };
    const onDrop = (e: DragEvent) => {
      setIsDraggingFile(false);
    };
    const onDragOver = (e: DragEvent) => {
      if (e.dataTransfer?.types?.includes('Files')) {
        e.preventDefault();
      }
    };
    window.addEventListener('dragenter', onDragEnter);
    window.addEventListener('dragleave', onDragLeave);
    window.addEventListener('drop', onDrop);
    window.addEventListener('dragover', onDragOver);
    return () => {
      window.removeEventListener('dragenter', onDragEnter);
      window.removeEventListener('dragleave', onDragLeave);
      window.removeEventListener('drop', onDrop);
      window.removeEventListener('dragover', onDragOver);
    };
  }, []);

  const handleOverlayDrop = useCallback(
    (e: React.DragEvent<HTMLDivElement>) => {
      e.preventDefault();
      setIsDraggingFile(false);
      const files = Array.from(e.dataTransfer.files || []);
      if (files.length > 0) {
        setUploadQueue(files.map((file) => file.name));
        Promise.all(files.map(uploadFile)).then((uploadedAttachments) => {
          const successfullyUploadedAttachments: Attachment[] =
            uploadedAttachments
              .filter((a) => !!a && typeof a.url === 'string')
              .map((a) => a as Attachment);
          setAttachments((current) => [
            ...current,
            ...successfullyUploadedAttachments,
          ]);
        });
      }
    },
    [setAttachments, uploadFile],
  );

  const placeholder = isJustifyMode ? 'Look something up' : 'Ask anything';
  const isEmptyState =
    messages.length === 0 && !webSearchLoading && !webSearchResults;
  const hasAttachments = attachments.length > 0 || uploadQueue.length > 0;

  return (
    <>
      {isDraggingFile && (
        <div
          className="fixed inset-0 z-[1000] flex flex-col items-center justify-center bg-[var(--chat-scrim)]"
          onDrop={handleOverlayDrop}
          onDragOver={(e) => e.preventDefault()}
        >
          <RoundedIcon
            icon={Attachment01Icon}
            className="mb-4 text-white"
            size={40}
          />
          <span className="mb-2 text-2xl font-semibold text-white">
            Drop your files here to chat
          </span>
        </div>
      )}
      <div
        className={`absolute inset-x-0 z-40 px-3 md:px-5 ${
          isEmptyState ? 'top-1/2 -translate-y-[30px]' : 'bottom-0 pb-3'
        }`}
      >
        <div className="relative mx-auto flex w-full max-w-[768px] flex-col">
          {isEmptyState && !input && (
            <SuggestedPrompts
              mode={isJustifyMode ? 'web' : null}
              input={input}
              onSelect={(prompt) => {
                setInput(prompt);
                focusInput();
              }}
            />
          )}
          <div
            className={`relative overflow-hidden border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] shadow-[0_8px_30px_var(--chat-shadow)] ${
              hasAttachments ? 'rounded-[28px]' : 'rounded-full'
            }`}
          >
            {hasAttachments && (
              <div
                data-testid="attachments-preview"
                className="flex items-end gap-2 overflow-x-auto px-4 pt-4"
              >
                {attachments.map((attachment) => (
                  <PreviewAttachment
                    key={attachment.url}
                    attachment={attachment}
                  />
                ))}

                {uploadQueue.map((filename) => (
                  <PreviewAttachment
                    key={filename}
                    attachment={{
                      url: '',
                      name: filename,
                      contentType: '',
                    }}
                    isUploading={true}
                  />
                ))}
              </div>
            )}
            <div className="relative flex w-full items-center">
              <Textarea
                data-testid="multimodal-input"
                ref={textareaRef}
                placeholder={placeholder}
                value={input}
                onChange={handleInput}
                className={`min-h-[58px] max-h-[180px] resize-none overflow-y-auto rounded-full border-0 bg-[var(--chat-elevated)] pb-[13px] pl-[58px] pr-[178px] pt-[21px] text-base leading-6 text-[var(--chat-ink)] shadow-none transition-[height] duration-150 placeholder:text-[var(--chat-hollow)] focus-visible:ring-0 sm:pr-[190px]${className ? ` ${className}` : ''}`}
                rows={1}
                autoFocus
                onKeyDown={(event) => {
                  if (
                    event.key === 'Enter' &&
                    !event.shiftKey &&
                    !event.nativeEvent.isComposing
                  ) {
                    event.preventDefault();

                    if (status !== 'ready') {
                      toast.error('Teya is answering now. Please wait.');
                    } else if (input.trim() || attachments.length > 0) {
                      submitForm();
                    }
                  }
                }}
              />
            </div>

            <div className="absolute bottom-[10px] left-[10px]">
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    className="flex size-[38px] items-center justify-center rounded-full bg-transparent p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]"
                    variant="ghost"
                    onClick={(event) => {
                      event.preventDefault();
                      fileInputRef.current?.click();
                    }}
                    aria-label="Attach images"
                  >
                    <RoundedIcon
                      icon={Add01Icon}
                      size={22}
                      strokeWidth={1.75}
                    />
                  </Button>
                </TooltipTrigger>
                <TooltipContent side="top">Attach images</TooltipContent>
              </Tooltip>
            </div>

            <div className="absolute bottom-[7px] right-[7px] flex items-center gap-0.5">
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    className={`h-10 rounded-full px-2.5 text-sm font-normal shadow-none ${
                      isJustifyMode
                        ? 'bg-[var(--chat-hover)] text-[var(--chat-ink)] hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]'
                        : 'bg-transparent text-[var(--chat-hollow)] hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]'
                    }`}
                    onClick={() => setIsJustifyMode((enabled) => !enabled)}
                    aria-label={
                      isJustifyMode
                        ? 'Turn off web thinking'
                        : 'Think with web search'
                    }
                    aria-pressed={isJustifyMode}
                  >
                    <RoundedIcon
                      icon={AiBrain01Icon}
                      size={18}
                      strokeWidth={1.6}
                    />
                    <span className="ml-1 hidden sm:inline">Think</span>
                  </Button>
                </TooltipTrigger>
                <TooltipContent side="top">
                  {isJustifyMode
                    ? 'Turn off web thinking'
                    : 'Think with web search'}
                </TooltipContent>
              </Tooltip>

              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    className={`size-10 rounded-full p-0 shadow-none ${
                      isListening
                        ? 'bg-[var(--chat-hover)] text-[var(--chat-ink)]'
                        : 'bg-transparent text-[var(--chat-ink)] hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]'
                    }`}
                    onClick={toggleDictation}
                    aria-label={
                      isListening ? 'Stop voice input' : 'Start voice input'
                    }
                    aria-pressed={isListening}
                  >
                    <RoundedIcon icon={Mic01Icon} size={19} strokeWidth={1.8} />
                  </Button>
                </TooltipTrigger>
                <TooltipContent side="top">
                  {isListening ? 'Stop voice input' : 'Start voice input'}
                </TooltipContent>
              </Tooltip>

              {status !== 'ready' ? (
                <StopButton stop={stop} setMessages={setMessages} />
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <SendButton
                      input={input}
                      isListening={isListening}
                      submitForm={submitForm}
                      toggleDictation={toggleDictation}
                      uploadQueue={uploadQueue}
                    />
                  </TooltipTrigger>
                  <TooltipContent
                    side="top"
                    className="flex items-center gap-2"
                  >
                    {input.trim() || uploadQueue.length > 0 ? (
                      <>
                        <span>Send message</span>
                        <HotkeyBadge hotkey={{ key: 'Enter' }} />
                      </>
                    ) : (
                      <span>
                        {isListening ? 'Stop voice input' : 'Start voice input'}
                      </span>
                    )}
                  </TooltipContent>
                </Tooltip>
              )}
            </div>

            <input
              type="file"
              accept="image/jpeg,image/png"
              className="pointer-events-none fixed -left-4 -top-4 size-0.5 opacity-0"
              ref={fileInputRef}
              multiple
              onChange={handleFileChange}
              tabIndex={-1}
            />
          </div>

          {isEmptyState && !input && !isJustifyMode && !hasAttachments && (
            <QuickActions
              onCreateImage={() => selectQuickAction('Create an image: ')}
              onLookUp={() => selectQuickAction('', true)}
              onWrite={() => selectQuickAction('Help me write or edit: ')}
            />
          )}

          {messages.length > 0 && (
            <p className="mt-2 hidden text-center text-xs leading-4 text-[var(--chat-hollow)] md:block">
              Teya can make mistakes. Check important information.
            </p>
          )}
        </div>
      </div>
      {isJustifyMode && (webSearchLoading || webSearchResults) && (
        <div className="absolute inset-x-3 bottom-[96px] z-30 mx-auto max-h-[calc(100svh-168px)] max-w-[768px] overflow-y-auto rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] p-4 text-[var(--chat-ink)] md:inset-x-5">
          {webSearchLoading && (
            <div className="flex items-center gap-2 text-sm text-[var(--chat-hollow)]">
              <span className="size-1.5 animate-pulse rounded-full bg-[var(--chat-hollow)]" />
              Searching the web
            </div>
          )}
          {webSearchResults && (
            <>
              {webSearchResults.formatted && (
                <div className="mb-4">
                  <Markdown>{webSearchResults.formatted}</Markdown>
                </div>
              )}
              {webSearchResults.results?.length > 0 && (
                <div className="mb-4">
                  <div className="mb-2 text-sm font-semibold">
                    Search results
                  </div>
                  <SearchResults
                    results={webSearchResults.results.map((r: any) => ({
                      title: r.title,
                      url: r.url,
                      content: r.snippet,
                    }))}
                  />
                </div>
              )}
              {webSearchResults.images?.length > 0 && (
                <div className="mb-4">
                  <div className="mb-2 text-sm font-semibold">Images</div>
                  <SearchResultsImageSection
                    images={webSearchResults.images.map((img: any) => ({
                      url: img.url,
                      description: img.alt,
                    }))}
                  />
                </div>
              )}
              {webSearchResults.videos?.length > 0 && (
                <div className="mb-4">
                  <div className="mb-2 text-sm font-semibold">Videos</div>
                  <VideoSearchResults
                    results={{
                      videos: webSearchResults.videos,
                      searchParameters: { q: '', type: '', engine: '' },
                    }}
                  />
                </div>
              )}
            </>
          )}
        </div>
      )}
    </>
  );
}

function QuickActions({
  onCreateImage,
  onLookUp,
  onWrite,
}: {
  onCreateImage: () => void;
  onLookUp: () => void;
  onWrite: () => void;
}) {
  return (
    <div className="mt-5 flex flex-col items-start gap-1.5 pl-3 sm:pl-5">
      <QuickAction
        icon={Image01Icon}
        label="Create an image"
        onClick={onCreateImage}
      />
      <QuickAction
        icon={PencilEdit01Icon}
        label="Write or edit"
        onClick={onWrite}
      />
      <QuickAction
        icon={Globe02Icon}
        label="Look something up"
        onClick={onLookUp}
      />
    </div>
  );
}

function QuickAction({
  icon: Icon,
  label,
  onClick,
}: {
  icon: IconSvgElement;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className="flex h-11 items-center gap-5 rounded-[10px] px-2 text-left text-[15px] text-[var(--chat-hollow)] transition-colors hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]"
      onClick={onClick}
    >
      <RoundedIcon icon={Icon} size={19} strokeWidth={1.6} />
      <span>{label}</span>
    </button>
  );
}

export const MultimodalInput = memo(
  PureMultimodalInput,
  (prevProps, nextProps) => {
    if (prevProps.input !== nextProps.input) return false;
    if (prevProps.status !== nextProps.status) return false;
    if (!equal(prevProps.attachments, nextProps.attachments)) return false;
    if (prevProps.chatPath !== nextProps.chatPath) return false;

    return true;
  },
);

function PureStopButton({
  stop,
  setMessages,
}: {
  stop: () => void;
  setMessages: Dispatch<SetStateAction<Array<Message>>>;
}) {
  return (
    <Button
      data-testid="stop-button"
      variant={undefined}
      className="flex size-11 items-center justify-center rounded-full bg-[var(--chat-press)] p-0 text-[var(--chat-paper)] shadow-none hover:bg-[var(--chat-press)] hover:opacity-90 disabled:bg-[var(--chat-press)] disabled:opacity-50"
      onClick={(event) => {
        event.preventDefault();
        stop();
        setMessages((messages) => messages);
      }}
    >
      <RoundedIcon icon={HugeStopIcon} size={15} strokeWidth={2} />
    </Button>
  );
}
const StopButton = memo(PureStopButton);

function PureSendButton({
  submitForm,
  input,
  isListening,
  toggleDictation,
  uploadQueue,
}: {
  submitForm: () => void;
  input: string;
  isListening: boolean;
  toggleDictation: () => void;
  uploadQueue: Array<string>;
}) {
  const hasMessage = input.trim().length > 0 || uploadQueue.length > 0;

  return (
    <Button
      data-testid="send-button"
      className="flex size-11 items-center justify-center rounded-full bg-[var(--chat-press)] p-0 text-[var(--chat-paper)] shadow-none hover:bg-[var(--chat-press)] hover:opacity-90"
      onClick={(event) => {
        event.preventDefault();
        if (hasMessage) {
          submitForm();
        } else {
          toggleDictation();
        }
      }}
      aria-label={
        hasMessage
          ? 'Send message'
          : isListening
            ? 'Stop voice input'
            : 'Start voice input'
      }
    >
      {hasMessage ? (
        <RoundedIcon icon={ArrowUp01Icon} size={19} strokeWidth={2} />
      ) : (
        <RoundedIcon
          icon={AudioWave01Icon}
          className={isListening ? 'animate-pulse' : ''}
          size={21}
          strokeWidth={1.9}
        />
      )}
    </Button>
  );
}

const SendButton = memo(PureSendButton, (prevProps, nextProps) => {
  if (prevProps.uploadQueue.length !== nextProps.uploadQueue.length)
    return false;
  if (prevProps.input !== nextProps.input) return false;
  if (prevProps.isListening !== nextProps.isListening) return false;
  return true;
});
