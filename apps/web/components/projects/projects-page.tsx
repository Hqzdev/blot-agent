'use client';

import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import type { Project, ProjectListItem } from '@/lib/projects/types';
import { fetcher } from '@/lib/utils';
import {
  AiIdeaIcon,
  Folder02Icon,
  Search01Icon,
} from '@hugeicons/core-free-icons';
import { formatDistanceToNow } from 'date-fns';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { FormEvent, useDeferredValue, useState } from 'react';
import { toast } from 'sonner';
import useSWR from 'swr';

export function ProjectsPage() {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query.trim());
  const [filter, setFilter] = useState<'all' | 'created'>('all');
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const url = deferredQuery
    ? `/app/api/projects?query=${encodeURIComponent(deferredQuery)}`
    : '/app/api/projects';
  const { data, error, isLoading, mutate } = useSWR<ProjectListItem[]>(
    url,
    fetcher,
    { keepPreviousData: true },
  );

  const handleCreated = async (project: Project) => {
    setIsCreateOpen(false);
    await mutate();
    router.push(`/projects/${project.id}`);
  };

  return (
    <main className="min-h-svh bg-[var(--chat-paper)] text-[var(--chat-ink)]">
      <div className="mx-auto w-full max-w-[920px] px-5 pb-16 pt-20 sm:px-8 sm:pt-24">
        <div className="flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
          <h1 className="text-2xl font-semibold tracking-tight">Projects</h1>
          <div className="flex w-full gap-2 sm:w-auto">
            <label htmlFor="project-search" className="relative flex-1 sm:w-64">
              <RoundedIcon
                icon={Search01Icon}
                size={16}
                className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--chat-hollow)]"
              />
              <Input
                id="project-search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search projects"
                aria-label="Search projects"
                maxLength={80}
                className="h-10 rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] pl-9 shadow-none"
              />
            </label>
            <Button
              type="button"
              onClick={() => setIsCreateOpen(true)}
              className="h-10 rounded-full px-5 shadow-none"
            >
              New
            </Button>
          </div>
        </div>

        <div className="mt-10 flex items-center gap-2">
          <FilterButton
            active={filter === 'all'}
            label="All"
            onClick={() => setFilter('all')}
          />
          <FilterButton
            active={filter === 'created'}
            label="Created by you"
            onClick={() => setFilter('created')}
          />
        </div>

        <section className="mt-10">
          {isLoading && !data ? (
            <ProjectGridSkeleton />
          ) : error ? (
            <StateMessage
              title="Projects could not be loaded"
              detail="Refresh the page and try again."
            />
          ) : data?.length ? (
            <div className="grid gap-3 sm:grid-cols-2">
              {data.map((project) => (
                <Link
                  key={project.id}
                  href={`/projects/${project.id}`}
                  className="group rounded-[18px] border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] p-5 transition-colors hover:bg-[var(--chat-hover)]"
                >
                  <div className="flex items-start gap-3">
                    <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-[var(--chat-hover)]">
                      <RoundedIcon icon={Folder02Icon} size={20} />
                    </div>
                    <div className="min-w-0">
                      <h2 className="truncate font-medium">{project.name}</h2>
                      <p className="mt-1 text-sm text-[var(--chat-hollow)]">
                        {project.chatCount}{' '}
                        {project.chatCount === 1 ? 'chat' : 'chats'} ·{' '}
                        {project.sourceCount}{' '}
                        {project.sourceCount === 1 ? 'source' : 'sources'}
                      </p>
                    </div>
                  </div>
                  <p className="mt-5 text-xs text-[var(--chat-hollow)]">
                    Updated{' '}
                    {formatDistanceToNow(new Date(project.updatedAt), {
                      addSuffix: true,
                    })}
                  </p>
                </Link>
              ))}
            </div>
          ) : (
            <StateMessage
              title={deferredQuery ? 'No matching projects' : 'No projects yet'}
              detail={
                deferredQuery
                  ? 'Try another search.'
                  : 'Create a project to keep related chats and sources together.'
              }
            />
          )}
        </section>
      </div>
      <CreateProjectDialog
        open={isCreateOpen}
        onOpenChange={setIsCreateOpen}
        onCreated={handleCreated}
      />
    </main>
  );
}

function FilterButton({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`h-9 rounded-full px-4 text-sm transition-colors ${
        active
          ? 'bg-[var(--chat-ink)] text-[var(--chat-paper)]'
          : 'text-[var(--chat-hollow)] hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]'
      }`}
    >
      {label}
    </button>
  );
}

function StateMessage({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="flex min-h-[360px] flex-col items-center justify-center text-center">
      <div className="flex size-14 items-center justify-center rounded-2xl bg-[var(--chat-hover)]">
        <RoundedIcon icon={Folder02Icon} size={27} />
      </div>
      <h2 className="mt-4 text-base font-medium">{title}</h2>
      <p className="mt-1 max-w-sm text-sm text-[var(--chat-hollow)]">
        {detail}
      </p>
    </div>
  );
}

function ProjectGridSkeleton() {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {[0, 1, 2, 3].map((item) => (
        <div
          key={item}
          className="h-32 animate-pulse rounded-[18px] bg-[var(--chat-hover)]"
        />
      ))}
    </div>
  );
}

function CreateProjectDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: (project: Project) => Promise<void>;
}) {
  const [name, setName] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const normalizedName = name.trim();
    if (!normalizedName || isSubmitting) {
      return;
    }
    setIsSubmitting(true);
    try {
      const response = await fetch('/app/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: normalizedName }),
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Project could not be created');
      }
      setName('');
      await onCreated(payload);
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : 'Project could not be created',
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
          onOpenChange(nextOpen);
        }
      }}
    >
      <DialogContent className="max-w-md rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] p-5 text-[var(--chat-ink)] shadow-2xl">
        <DialogHeader>
          <DialogTitle className="text-base font-medium">
            Create project
          </DialogTitle>
        </DialogHeader>
        <form onSubmit={submit}>
          <label className="text-sm font-medium" htmlFor="project-name">
            Project name
          </label>
          <Input
            id="project-name"
            autoFocus
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Copenhagen Trip"
            maxLength={80}
            disabled={isSubmitting}
            className="mt-2 h-10 rounded-[10px] border-[var(--chat-hairline)] bg-transparent shadow-none"
          />
          <div className="mt-3 flex gap-3 rounded-[12px] bg-[var(--chat-hover)] p-3 text-sm text-[var(--chat-hollow)]">
            <RoundedIcon
              icon={AiIdeaIcon}
              size={18}
              className="mt-0.5 shrink-0 text-[var(--chat-ink)]"
            />
            <p>
              Projects keep chats, files, and instructions in one place so you
              can stay focused.
            </p>
          </div>
          <div className="mt-5">
            <p className="text-sm font-medium">Project-only memory</p>
            <p className="mt-1 text-sm text-[var(--chat-hollow)]">
              This project can only access its own chats and sources.
            </p>
          </div>
          <DialogFooter className="mt-6">
            <Button
              type="button"
              variant="ghost"
              onClick={() => onOpenChange(false)}
              disabled={isSubmitting}
              className="rounded-full"
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={!name.trim() || isSubmitting}
              className="rounded-full"
            >
              {isSubmitting ? 'Creating…' : 'Create project'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
