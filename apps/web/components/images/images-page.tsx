'use client';

import type { LibraryItem, LibraryListResult } from '@teya/contracts';
import {
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  Download,
  ImageIcon,
  Mic,
  Palette,
  Paperclip,
  Sparkles,
  Sun,
  UserRound,
  Waves,
  X,
} from 'lucide-react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { type FormEvent, useCallback, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import useSWR from 'swr';

import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { useDictation } from '@/hooks/use-dictation';
import { cn, fetcher, generateUUID } from '@/lib/utils';

const galleryApi =
  '/app/api/library/items?deleted=false&direction=desc&limit=100&sort=modified&source=generated&tab=images';

const presets = [
  {
    background:
      'linear-gradient(145deg, #78c8ff 0%, #ffd3ad 48%, #f36f9d 100%)',
    icon: Sparkles,
    label: 'Storybook',
    prompt:
      'A richly detailed storybook illustration with a warm, magical atmosphere',
  },
  {
    background:
      'linear-gradient(145deg, #172142 0%, #5b5be7 52%, #ffaf5f 100%)',
    icon: UserRound,
    label: 'Anime',
    prompt:
      'An expressive anime character portrait with dramatic cinematic lighting',
  },
  {
    background:
      'linear-gradient(145deg, #163e5a 0%, #43b9b1 48%, #f3c8a1 100%)',
    icon: Waves,
    label: 'Underwater',
    prompt:
      'A dreamy underwater portrait with sunbeams, bubbles, and flowing hair',
  },
  {
    background:
      'linear-gradient(145deg, #f5c28f 0%, #de8b61 55%, #746b4c 100%)',
    icon: Sun,
    label: 'Summer list',
    prompt:
      'A playful summer bucket list poster with charming illustrated objects',
  },
  {
    background:
      'linear-gradient(145deg, #c5a5ed 0%, #7455a9 55%, #e89dbe 100%)',
    icon: Palette,
    label: 'Sticker pack',
    prompt:
      'A cohesive collection of colorful editorial stickers on a clean background',
  },
] as const;

export function ImagesPage() {
  const router = useRouter();
  const presetsRef = useRef<HTMLDivElement>(null);
  const promptRef = useRef<HTMLInputElement>(null);
  const [prompt, setPrompt] = useState('');
  const [preview, setPreview] = useState<LibraryItem | null>(null);
  const { data, error, isLoading, mutate } = useSWR<LibraryListResult>(
    galleryApi,
    fetcher,
  );

  const addTranscript = useCallback((transcript: string) => {
    setPrompt((current) =>
      current.trim() ? `${current.trimEnd()} ${transcript}` : transcript,
    );
    requestAnimationFrame(() => promptRef.current?.focus());
  }, []);

  const showDictationError = useCallback((message: string) => {
    toast.error(message);
  }, []);

  const { isListening, toggle: toggleDictation } = useDictation({
    onError: showDictationError,
    onTranscript: addTranscript,
  });

  const images = useMemo(
    () =>
      (data?.items ?? []).filter(
        (item) => item.contentType?.startsWith('image/') ?? false,
      ),
    [data?.items],
  );

  const openReferenceChat = useCallback(
    (value: string) => {
      const description = value.trim();
      if (description) {
        window.localStorage.setItem(
          'input',
          JSON.stringify(`Create an image: ${description}`),
        );
      }
      router.push('/chat');
    },
    [router],
  );

  const generateImage = useCallback(
    (value: string) => {
      const description = value.trim();
      if (!description) {
        return;
      }
      const chatId = generateUUID();
      window.sessionStorage.setItem(
        `teya:image-draft:${chatId}`,
        `Create an image: ${description}`,
      );
      router.push(`/images/new/${chatId}`);
    },
    [router],
  );

  const submitPrompt = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (prompt.trim()) {
      generateImage(prompt);
    }
  };

  const selectPreset = (value: string) => {
    setPrompt(value);
    promptRef.current?.focus();
  };

  const scrollPresets = (direction: -1 | 1) => {
    presetsRef.current?.scrollBy({
      behavior: 'smooth',
      left: direction * 360,
    });
  };

  return (
    <main className="h-svh overflow-y-auto bg-[var(--chat-paper)] text-[var(--chat-ink)]">
      <div className="mx-auto w-full max-w-[1480px] px-4 pb-16 pt-20 sm:px-7 sm:pt-24 lg:px-10 lg:pt-28">
        <section className="mx-auto w-full max-w-[760px]">
          <h1 className="text-[26px] font-semibold tracking-[-0.03em]">
            Images
          </h1>

          <form
            onSubmit={submitPrompt}
            className="mt-5 flex h-[54px] items-center rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] px-2 shadow-[0_8px_30px_var(--chat-shadow)]"
          >
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="size-9 shrink-0 rounded-full text-[var(--chat-mid-ash)]"
              aria-label="Add a reference image in chat"
              onClick={() =>
                openReferenceChat(
                  prompt ||
                    'Use a reference image that I will attach to create a new image',
                )
              }
            >
              <Paperclip className="size-[18px]" />
            </Button>
            <label className="sr-only" htmlFor="image-prompt">
              Describe a new image
            </label>
            <input
              ref={promptRef}
              id="image-prompt"
              value={prompt}
              onChange={(event) => setPrompt(event.target.value)}
              placeholder="Describe a new image"
              autoComplete="off"
              className="h-full min-w-0 flex-1 bg-transparent px-2 text-[15px] outline-none placeholder:text-[var(--chat-hollow)]"
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className={cn(
                'size-9 shrink-0 rounded-full text-[var(--chat-mid-ash)]',
                isListening && 'bg-[var(--chat-hover)] text-[var(--chat-ink)]',
              )}
              aria-label={
                isListening ? 'Stop voice input' : 'Start voice input'
              }
              aria-pressed={isListening}
              onClick={toggleDictation}
            >
              <Mic className="size-[18px]" />
            </Button>
            <Button
              type="submit"
              size="icon"
              disabled={!prompt.trim()}
              aria-label="Create image"
              className="size-9 shrink-0 rounded-full bg-[var(--chat-press)] text-[var(--chat-paper)] shadow-none hover:bg-[var(--chat-press)] disabled:bg-[var(--chat-hover)] disabled:text-[var(--chat-hollow)]"
            >
              <ArrowUp className="size-[18px]" strokeWidth={2.2} />
            </Button>
          </form>

          <div className="mt-11 flex items-center">
            <h2 className="text-[15px] font-semibold">Create an image</h2>
            <div className="ml-auto flex gap-2">
              <Button
                type="button"
                variant="outline"
                size="icon"
                className="size-8 rounded-full border-[var(--chat-hairline)] bg-transparent"
                aria-label="Previous image styles"
                onClick={() => scrollPresets(-1)}
              >
                <ArrowLeft className="size-4" />
              </Button>
              <Button
                type="button"
                variant="outline"
                size="icon"
                className="size-8 rounded-full border-[var(--chat-hairline)] bg-transparent"
                aria-label="Next image styles"
                onClick={() => scrollPresets(1)}
              >
                <ArrowRight className="size-4" />
              </Button>
            </div>
          </div>

          <div
            ref={presetsRef}
            className="mt-4 flex snap-x gap-3 overflow-x-auto pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          >
            {presets.map((preset) => (
              <button
                key={preset.label}
                type="button"
                className="group relative h-[154px] w-[126px] shrink-0 snap-start overflow-hidden rounded-[18px] text-left text-white shadow-sm transition-transform hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--chat-ink)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--chat-paper)]"
                style={{ background: preset.background }}
                onClick={() => selectPreset(preset.prompt)}
                aria-label={`Use ${preset.label} style`}
              >
                <span className="absolute -right-6 -top-6 size-24 rounded-full bg-white/20 blur-xl" />
                <span className="absolute -bottom-5 -left-6 size-28 rounded-full bg-black/20 blur-xl" />
                <span className="absolute inset-0 flex items-center justify-center">
                  <span className="flex size-16 items-center justify-center rounded-[22px] border border-white/30 bg-white/20 shadow-lg backdrop-blur-md transition-transform group-hover:scale-105">
                    <preset.icon className="size-8" strokeWidth={1.5} />
                  </span>
                </span>
                <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/55 to-transparent px-3 pb-3 pt-8 text-[12px] font-medium">
                  {preset.label}
                </span>
              </button>
            ))}
          </div>
        </section>

        <section className="mt-12">
          <h2 className="mx-auto mb-3 w-full max-w-[760px] text-[15px] font-semibold">
            My images
          </h2>
          {isLoading ? (
            <ImageGallerySkeleton />
          ) : error ? (
            <GalleryState
              icon={<X className="size-6" />}
              title="Could not load your images"
              action={
                <Button
                  variant="outline"
                  className="mt-4 rounded-full"
                  onClick={() => void mutate()}
                >
                  Try again
                </Button>
              }
            />
          ) : images.length === 0 ? (
            <GalleryState
              icon={<ImageIcon className="size-6" />}
              title="Your generated images will appear here"
              description="Describe an image above to create your first one."
            />
          ) : (
            <div className="grid grid-cols-2 gap-1 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-5">
              {images.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="group relative aspect-square overflow-hidden bg-[var(--chat-sidebar-mist)] focus-visible:z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--chat-ink)]"
                  aria-label={`Preview ${item.name}`}
                  onClick={() => setPreview(item)}
                >
                  <Image
                    src={thumbnailUrl(item)}
                    alt={item.name}
                    fill
                    sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, (max-width: 1536px) 25vw, 20vw"
                    className="object-cover transition-transform duration-300 group-hover:scale-[1.02]"
                    unoptimized
                  />
                  <span className="absolute inset-x-0 bottom-0 translate-y-full bg-gradient-to-t from-black/70 to-transparent px-4 pb-3 pt-12 text-left text-xs font-medium text-white transition-transform duration-200 group-hover:translate-y-0 group-focus-visible:translate-y-0">
                    {item.name}
                  </span>
                </button>
              ))}
            </div>
          )}
        </section>
      </div>

      <ImagePreview item={preview} onClose={() => setPreview(null)} />
    </main>
  );
}

function ImageGallerySkeleton() {
  return (
    <div
      className="grid grid-cols-2 gap-1 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-5"
      aria-label="Loading images"
    >
      {Array.from({ length: 10 }, (_, index) => (
        <div
          key={index}
          className="aspect-square animate-pulse bg-[var(--chat-hover)]"
        />
      ))}
    </div>
  );
}

function GalleryState({
  action,
  description,
  icon,
  title,
}: {
  action?: React.ReactNode;
  description?: string;
  icon: React.ReactNode;
  title: string;
}) {
  return (
    <div className="flex min-h-[300px] flex-col items-center justify-center rounded-[24px] border border-dashed border-[var(--chat-hairline)] text-center">
      <span className="flex size-12 items-center justify-center rounded-[16px] bg-[var(--chat-hover)] text-[var(--chat-mid-ash)]">
        {icon}
      </span>
      <p className="mt-4 text-sm font-medium">{title}</p>
      {description && (
        <p className="mt-1 text-sm text-[var(--chat-hollow)]">{description}</p>
      )}
      {action}
    </div>
  );
}

function ImagePreview({
  item,
  onClose,
}: {
  item: LibraryItem | null;
  onClose: () => void;
}) {
  return (
    <Dialog open={Boolean(item)} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-[920px] overflow-hidden rounded-[24px] border-[var(--chat-hairline)] bg-[var(--chat-paper)] p-0">
        {item && (
          <>
            <DialogHeader className="sr-only">
              <DialogTitle>{item.name}</DialogTitle>
              <DialogDescription>Generated image preview</DialogDescription>
            </DialogHeader>
            <div className="relative aspect-square max-h-[75vh] w-full bg-[var(--chat-sidebar-mist)]">
              <Image
                src={thumbnailUrl(item)}
                alt={item.name}
                fill
                sizes="min(920px, 100vw)"
                className="object-contain"
                unoptimized
              />
            </div>
            <div className="flex items-center gap-3 border-t border-[var(--chat-hairline)] px-5 py-4">
              <p className="min-w-0 flex-1 truncate text-sm font-medium">
                {item.name}
              </p>
              <Button
                asChild
                variant="outline"
                className="rounded-full border-[var(--chat-hairline)]"
              >
                <a href={`/app/api/library/items/${item.id}/download`}>
                  <Download className="mr-2 size-4" />
                  Download
                </a>
              </Button>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function thumbnailUrl(item: LibraryItem): string {
  return item.url ?? `/app/api/library/items/${item.id}/thumbnail`;
}
