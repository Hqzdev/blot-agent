'use client';

import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type {
  Project,
  ProjectChat,
  ProjectDetails,
  ProjectSource,
} from '@/lib/projects/types';
import { fetcher, generateUUID } from '@/lib/utils';
import {
  Add01Icon,
  Alert02Icon,
  ArrowUp01Icon,
  Attachment01Icon,
  Delete02Icon,
  File01Icon,
  Folder02Icon,
  MoreHorizontalIcon,
  PencilEdit01Icon,
  Upload01Icon,
} from '@hugeicons/core-free-icons';
import { formatDistanceToNow } from 'date-fns';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { ChangeEvent, FormEvent, useRef, useState } from 'react';
import { toast } from 'sonner';
import useSWR, { useSWRConfig } from 'swr';

const sourceAccept = [
  '.txt',
  '.md',
  '.markdown',
  '.csv',
  '.json',
  '.pdf',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.py',
  '.java',
  '.c',
  '.cpp',
  '.h',
  '.hpp',
  '.cs',
  '.go',
  '.rs',
  '.rb',
  '.php',
  '.swift',
  '.kt',
  '.kts',
  '.sql',
  '.html',
  '.css',
  '.scss',
  '.yaml',
  '.yml',
  '.xml',
  '.sh',
].join(',');

export function ProjectPage({ projectId }: { projectId: string }) {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [prompt, setPrompt] = useState('');
  const [isRenameOpen, setIsRenameOpen] = useState(false);
  const [isDeleteOpen, setIsDeleteOpen] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [deletingSourceId, setDeletingSourceId] = useState<string | null>(null);
  const { data, error, isLoading, mutate } = useSWR<ProjectDetails>(
    `/app/api/projects/${projectId}`,
    fetcher,
  );

  const startChat = (event: FormEvent) => {
    event.preventDefault();
    const draft = prompt.trim();
    if (!draft) {
      return;
    }
    const chatId = generateUUID();
    const storageKey = `teya:project-draft:${chatId}`;
    sessionStorage.setItem(storageKey, draft);
    router.push(`/projects/${projectId}/new/${chatId}`);
  };

  const uploadSource = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file || isUploading) {
      return;
    }
    setIsUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const response = await fetch(`/app/api/projects/${projectId}/sources`, {
        method: 'POST',
        body: formData,
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Source could not be uploaded');
      }
      await mutate();
      toast.success('Source uploaded');
    } catch (uploadError) {
      toast.error(
        uploadError instanceof Error
          ? uploadError.message
          : 'Source could not be uploaded',
      );
    } finally {
      setIsUploading(false);
    }
  };

  const deleteSource = async (source: ProjectSource) => {
    if (deletingSourceId) {
      return;
    }
    setDeletingSourceId(source.id);
    try {
      const response = await fetch(
        `/app/api/projects/${projectId}/sources/${source.id}`,
        { method: 'DELETE' },
      );
      if (!response.ok) {
        const payload = await response.json();
        throw new Error(payload.error || 'Source could not be deleted');
      }
      await mutate();
      toast.success('Source deleted');
    } catch (deleteError) {
      toast.error(
        deleteError instanceof Error
          ? deleteError.message
          : 'Source could not be deleted',
      );
    } finally {
      setDeletingSourceId(null);
    }
  };

  if (isLoading) {
    return <ProjectPageSkeleton />;
  }

  if (error || !data) {
    return (
      <main className="flex min-h-svh items-center justify-center bg-[var(--chat-paper)] px-6 text-center text-[var(--chat-ink)]">
        <div>
          <h1 className="text-lg font-medium">Project could not be loaded</h1>
          <Button
            className="mt-4 rounded-full"
            onClick={() => router.push('/projects')}
          >
            Back to projects
          </Button>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-svh bg-[var(--chat-paper)] text-[var(--chat-ink)]">
      <div className="mx-auto w-full max-w-[760px] px-4 pb-20 pt-20 sm:px-6 sm:pt-24">
        <div className="flex items-center">
          <div className="flex min-w-0 items-center gap-3">
            <RoundedIcon icon={Folder02Icon} size={24} />
            <h1 className="truncate text-2xl font-semibold">
              {data.project.name}
            </h1>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                className="ml-auto size-9 rounded-full p-0 shadow-none"
                aria-label="Project menu"
              >
                <RoundedIcon icon={MoreHorizontalIcon} size={19} />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="min-w-44 rounded-xl border-[var(--chat-hairline)] bg-[var(--chat-elevated)] p-1 shadow-lg"
            >
              <DropdownMenuItem
                onSelect={() => setIsRenameOpen(true)}
                className="rounded-lg"
              >
                <RoundedIcon icon={PencilEdit01Icon} size={17} />
                Rename
              </DropdownMenuItem>
              <DropdownMenuItem
                onSelect={() => setIsDeleteOpen(true)}
                className="rounded-lg text-destructive focus:text-destructive"
              >
                <RoundedIcon icon={Delete02Icon} size={17} />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <form
          onSubmit={startChat}
          className="mt-7 flex min-h-12 items-end gap-2 rounded-[18px] bg-[var(--chat-elevated)] p-2 pl-4 shadow-[0_0_0_1px_var(--chat-hairline)]"
        >
          <RoundedIcon
            icon={Add01Icon}
            size={19}
            className="mb-2 text-[var(--chat-hollow)]"
          />
          <textarea
            value={prompt}
            onChange={(event) => setPrompt(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                event.currentTarget.form?.requestSubmit();
              }
            }}
            rows={1}
            placeholder={`New chat in ${data.project.name}`}
            aria-label={`New chat in ${data.project.name}`}
            className="min-h-9 flex-1 resize-none bg-transparent py-2 text-sm outline-none placeholder:text-[var(--chat-hollow)]"
          />
          <Button
            type="submit"
            disabled={!prompt.trim()}
            className="size-9 shrink-0 rounded-full p-0 shadow-none"
            aria-label="Start chat"
          >
            <RoundedIcon icon={ArrowUp01Icon} size={18} />
          </Button>
        </form>

        <Tabs defaultValue="chats" className="mt-6">
          <TabsList className="h-auto gap-1 bg-transparent p-0">
            <TabsTrigger
              value="chats"
              className="rounded-full px-4 py-2 shadow-none data-[state=active]:bg-[var(--chat-hover)] data-[state=active]:shadow-none"
            >
              Chats
            </TabsTrigger>
            <TabsTrigger
              value="sources"
              className="rounded-full px-4 py-2 shadow-none data-[state=active]:bg-[var(--chat-hover)] data-[state=active]:shadow-none"
            >
              Sources
            </TabsTrigger>
          </TabsList>
          <TabsContent value="chats" className="mt-5">
            <ProjectChats chats={data.chats} projectId={projectId} />
          </TabsContent>
          <TabsContent value="sources" className="mt-5">
            <ProjectSources
              sources={data.sources}
              isUploading={isUploading}
              deletingSourceId={deletingSourceId}
              onUpload={() => fileInputRef.current?.click()}
              onDelete={deleteSource}
            />
          </TabsContent>
        </Tabs>
      </div>

      <input
        ref={fileInputRef}
        type="file"
        accept={sourceAccept}
        onChange={uploadSource}
        className="hidden"
      />
      <RenameProjectDialog
        project={data.project}
        open={isRenameOpen}
        onOpenChange={setIsRenameOpen}
        onRenamed={mutate}
      />
      <DeleteProjectDialog
        project={data.project}
        open={isDeleteOpen}
        onOpenChange={setIsDeleteOpen}
      />
    </main>
  );
}

function ProjectChats({
  chats,
  projectId,
}: {
  chats: ProjectChat[];
  projectId: string;
}) {
  if (chats.length === 0) {
    return (
      <ProjectEmptyState
        icon={Folder02Icon}
        title="No chats yet"
        detail="Chats in this project will live here."
      />
    );
  }
  return (
    <div className="divide-y divide-[var(--chat-hairline)] rounded-[16px] border border-[var(--chat-hairline)]">
      {chats.map((chat) => (
        <Link
          key={chat.id}
          href={`/projects/${projectId}/chat/${chat.id}`}
          className="flex items-center gap-3 px-4 py-3 transition-colors first:rounded-t-[16px] last:rounded-b-[16px] hover:bg-[var(--chat-hover)]"
        >
          <RoundedIcon
            icon={Folder02Icon}
            size={18}
            className="text-[var(--chat-hollow)]"
          />
          <span className="min-w-0 flex-1 truncate text-sm">{chat.title}</span>
          <span className="text-xs text-[var(--chat-hollow)]">
            {formatDistanceToNow(new Date(chat.updatedAt), { addSuffix: true })}
          </span>
        </Link>
      ))}
    </div>
  );
}

function ProjectSources({
  sources,
  isUploading,
  deletingSourceId,
  onUpload,
  onDelete,
}: {
  sources: ProjectSource[];
  isUploading: boolean;
  deletingSourceId: string | null;
  onUpload: () => void;
  onDelete: (source: ProjectSource) => void;
}) {
  return (
    <div>
      <div className="flex items-center justify-between">
        <p className="text-sm text-[var(--chat-hollow)]">
          {sources.length} of 20 sources
        </p>
        <Button
          type="button"
          size="sm"
          onClick={onUpload}
          disabled={isUploading || sources.length >= 20}
          className="rounded-full"
        >
          <RoundedIcon icon={Upload01Icon} size={16} />
          {isUploading ? 'Uploading…' : 'Add source'}
        </Button>
      </div>
      {sources.length === 0 ? (
        <div className="mt-5">
          <ProjectEmptyState
            icon={Attachment01Icon}
            title="Give Teya more context"
            detail="Upload text, code, CSV, JSON, Markdown, or PDF files for this project."
            action={
              <Button
                type="button"
                size="sm"
                onClick={onUpload}
                disabled={isUploading}
                className="mt-4 rounded-full"
              >
                Add sources
              </Button>
            }
          />
        </div>
      ) : (
        <div className="mt-4 divide-y divide-[var(--chat-hairline)] rounded-[16px] border border-[var(--chat-hairline)]">
          {sources.map((source) => (
            <div key={source.id} className="flex items-center gap-3 px-4 py-3">
              <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-[var(--chat-hover)]">
                <RoundedIcon icon={File01Icon} size={18} />
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{source.name}</p>
                <p className="mt-0.5 text-xs text-[var(--chat-hollow)]">
                  {formatFileSize(source.size)}
                </p>
              </div>
              <Button
                type="button"
                variant="ghost"
                onClick={() => onDelete(source)}
                disabled={deletingSourceId === source.id}
                className="size-8 rounded-full p-0 text-[var(--chat-hollow)] hover:text-destructive"
                aria-label={`Delete ${source.name}`}
              >
                <RoundedIcon icon={Delete02Icon} size={17} />
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function ProjectEmptyState({
  icon,
  title,
  detail,
  action,
}: {
  icon: Parameters<typeof RoundedIcon>[0]['icon'];
  title: string;
  detail: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex min-h-[300px] flex-col items-center justify-center rounded-[18px] border border-dashed border-[var(--chat-hairline)] px-6 text-center">
      <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--chat-hover)]">
        <RoundedIcon icon={icon} size={23} />
      </div>
      <h2 className="mt-4 text-sm font-medium">{title}</h2>
      <p className="mt-1 max-w-sm text-sm text-[var(--chat-hollow)]">
        {detail}
      </p>
      {action}
    </div>
  );
}

function RenameProjectDialog({
  project,
  open,
  onOpenChange,
  onRenamed,
}: {
  project: Project;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRenamed: () => Promise<ProjectDetails | undefined>;
}) {
  const [name, setName] = useState(project.name);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const normalizedName = name.trim();
    if (!normalizedName || normalizedName === project.name) {
      return;
    }
    setIsSubmitting(true);
    try {
      const response = await fetch(`/app/api/projects/${project.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: normalizedName }),
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Project could not be renamed');
      }
      await onRenamed();
      onOpenChange(false);
      toast.success('Project renamed');
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : 'Project could not be renamed',
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!isSubmitting) {
          setName(project.name);
          onOpenChange(nextOpen);
        }
      }}
    >
      <DialogContent className="max-w-md rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] text-[var(--chat-ink)]">
        <DialogHeader>
          <DialogTitle className="text-base">Rename project</DialogTitle>
        </DialogHeader>
        <form onSubmit={submit}>
          <Input
            value={name}
            onChange={(event) => setName(event.target.value)}
            maxLength={80}
            autoFocus
            disabled={isSubmitting}
            className="rounded-[10px] border-[var(--chat-hairline)] bg-transparent shadow-none"
          />
          <DialogFooter className="mt-5">
            <Button
              type="button"
              variant="ghost"
              onClick={() => onOpenChange(false)}
              className="rounded-full"
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={
                isSubmitting || !name.trim() || name.trim() === project.name
              }
              className="rounded-full"
            >
              {isSubmitting ? 'Renaming…' : 'Rename'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function DeleteProjectDialog({
  project,
  open,
  onOpenChange,
}: {
  project: Project;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const router = useRouter();
  const { mutate } = useSWRConfig();
  const [isDeleting, setIsDeleting] = useState(false);

  const deleteProject = async () => {
    if (isDeleting) {
      return;
    }
    setIsDeleting(true);
    try {
      const response = await fetch(`/app/api/projects/${project.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) {
        const payload = await response.json();
        throw new Error(payload.error || 'Project could not be deleted');
      }
      await mutate('/app/api/projects');
      router.push('/projects');
      router.refresh();
      toast.success('Project deleted');
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : 'Project could not be deleted',
      );
      setIsDeleting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] text-[var(--chat-ink)]">
        <DialogHeader>
          <DialogTitle className="text-base">Delete project</DialogTitle>
        </DialogHeader>
        <div className="flex gap-3 rounded-[12px] bg-[var(--chat-hover)] p-3 text-sm">
          <RoundedIcon
            icon={Alert02Icon}
            size={18}
            className="shrink-0 text-destructive"
          />
          <p>
            This permanently deletes {project.name}, all of its chats, and all
            uploaded sources.
          </p>
        </div>
        <DialogFooter>
          <Button
            type="button"
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isDeleting}
            className="rounded-full"
          >
            Cancel
          </Button>
          <Button
            type="button"
            onClick={deleteProject}
            disabled={isDeleting}
            className="rounded-full bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            {isDeleting ? 'Deleting…' : 'Delete project'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ProjectPageSkeleton() {
  return (
    <main className="min-h-svh bg-[var(--chat-paper)] px-5 pt-24">
      <div className="mx-auto max-w-[760px] animate-pulse">
        <div className="h-8 w-52 rounded-lg bg-[var(--chat-hover)]" />
        <div className="mt-7 h-14 rounded-[18px] bg-[var(--chat-hover)]" />
        <div className="mt-7 h-80 rounded-[18px] bg-[var(--chat-hover)]" />
      </div>
    </main>
  );
}

function formatFileSize(size: number) {
  if (size < 1024) {
    return `${size} B`;
  }
  if (size < 1024 * 1024) {
    return `${Math.round(size / 1024)} KB`;
  }
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}
