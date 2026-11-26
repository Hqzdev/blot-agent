'use client';

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import { Textarea } from '@/components/ui/textarea';
import { cn, fetcher } from '@/lib/utils';
import {
  AiBrain01Icon,
  AiSearchIcon,
  Bug01Icon,
  CheckmarkCircle04Icon,
  DatabaseIcon,
  InspectCodeIcon,
  Notebook01Icon,
  PencilIcon,
  PlusSignIcon,
  Search01Icon,
  SparklesIcon,
  StickyNote01Icon,
  TaskAdd02Icon,
  TextCheckIcon,
} from '@hugeicons/core-free-icons';
import type { IconSvgElement } from '@hugeicons/react';
import type {
  SkillCategory,
  SkillDetail,
  SkillInput,
  SkillSummary,
} from '@teya/contracts';
import { FormEvent, useDeferredValue, useMemo, useState } from 'react';
import { toast } from 'sonner';
import useSWR from 'swr';

const categoryOrder: Array<{
  id: SkillCategory;
  label: string;
}> = [
  { id: 'featured', label: 'Featured' },
  { id: 'productivity', label: 'Productivity' },
  { id: 'creativity', label: 'Creativity' },
  { id: 'developer_tools', label: 'Developer Tools' },
  { id: 'personal', label: 'Your skills' },
];

const iconByKey: Record<string, IconSvgElement> = {
  analytics: AiBrain01Icon,
  copy: TextCheckIcon,
  database: DatabaseIcon,
  debug: Bug01Icon,
  design: AiBrain01Icon,
  ideas: SparklesIcon,
  meeting: StickyNote01Icon,
  planning: TaskAdd02Icon,
  research: AiSearchIcon,
  review: InspectCodeIcon,
  sparkles: SparklesIcon,
  study: Notebook01Icon,
  writing: PencilIcon,
};

const iconStyleByKey: Record<string, string> = {
  analytics: 'bg-sky-500/15 text-sky-500',
  copy: 'bg-rose-500/15 text-rose-500',
  database: 'bg-emerald-500/15 text-emerald-500',
  debug: 'bg-red-500/15 text-red-500',
  design: 'bg-violet-500/15 text-violet-500',
  ideas: 'bg-amber-500/15 text-amber-500',
  meeting: 'bg-cyan-500/15 text-cyan-500',
  planning: 'bg-blue-500/15 text-blue-500',
  research: 'bg-indigo-500/15 text-indigo-500',
  review: 'bg-slate-500/15 text-slate-500',
  sparkles: 'bg-fuchsia-500/15 text-fuchsia-500',
  study: 'bg-orange-500/15 text-orange-500',
  writing: 'bg-pink-500/15 text-pink-500',
};

export function SkillsLibraryPage() {
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query.trim());
  const [selectedSkill, setSelectedSkill] = useState<SkillDetail | null>(null);
  const [isDetailLoading, setIsDetailLoading] = useState(false);
  const [editorSkill, setEditorSkill] = useState<
    SkillDetail | null | undefined
  >(undefined);
  const [pendingSkillId, setPendingSkillId] = useState<string | null>(null);
  const [deleteSkill, setDeleteSkill] = useState<SkillDetail | null>(null);
  const url = deferredQuery
    ? `/app/api/skills?query=${encodeURIComponent(deferredQuery)}`
    : '/app/api/skills';
  const { data, error, isLoading, mutate } = useSWR<SkillSummary[]>(
    url,
    fetcher,
    { keepPreviousData: true },
  );

  const installedSkills = useMemo(
    () => data?.filter((skill) => skill.installed) ?? [],
    [data],
  );

  const groupedSkills = useMemo(
    () =>
      categoryOrder.map((category) => ({
        ...category,
        skills: data?.filter((skill) => skill.category === category.id) ?? [],
      })),
    [data],
  );

  const openDetail = async (skill: SkillSummary) => {
    setIsDetailLoading(true);
    try {
      const response = await fetch(`/app/api/skills/${skill.id}`);
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Skill could not be loaded');
      }
      setSelectedSkill(payload);
    } catch (loadError) {
      toast.error(
        loadError instanceof Error
          ? loadError.message
          : 'Skill could not be loaded',
      );
    } finally {
      setIsDetailLoading(false);
    }
  };

  const changeInstallation = async (
    skill: SkillSummary | SkillDetail,
    installed: boolean,
  ) => {
    if (pendingSkillId) {
      return;
    }
    setPendingSkillId(skill.id);
    try {
      const response = await fetch(`/app/api/skills/${skill.id}/installation`, {
        method: installed ? 'PUT' : 'DELETE',
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Skill could not be updated');
      }
      setSelectedSkill((current) =>
        current?.id === skill.id ? { ...current, installed } : current,
      );
      await mutate();
      toast.success(installed ? 'Skill installed' : 'Skill removed');
    } catch (installationError) {
      toast.error(
        installationError instanceof Error
          ? installationError.message
          : 'Skill could not be updated',
      );
    } finally {
      setPendingSkillId(null);
    }
  };

  const deleteCustomSkill = async () => {
    if (!deleteSkill || pendingSkillId) {
      return;
    }
    setPendingSkillId(deleteSkill.id);
    try {
      const response = await fetch(`/app/api/skills/${deleteSkill.id}`, {
        method: 'DELETE',
      });
      if (!response.ok) {
        const payload = await response.json();
        throw new Error(payload.error || 'Skill could not be deleted');
      }
      setDeleteSkill(null);
      setSelectedSkill(null);
      setEditorSkill(undefined);
      await mutate();
      toast.success('Skill deleted');
    } catch (deleteError) {
      toast.error(
        deleteError instanceof Error
          ? deleteError.message
          : 'Skill could not be deleted',
      );
    } finally {
      setPendingSkillId(null);
    }
  };

  return (
    <main className="min-h-svh bg-[var(--chat-paper)] text-[var(--chat-ink)]">
      <div className="mx-auto w-full max-w-[940px] px-5 pb-20 pt-20 sm:px-8 sm:pt-24">
        <header className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">Skills</h1>
            <p className="mt-1 text-sm text-[var(--chat-hollow)]">
              Give Teya specialist workflows it can use when helpful.
            </p>
          </div>
          <div className="flex w-full gap-2 sm:w-auto">
            <label htmlFor="skill-search" className="relative flex-1 sm:w-64">
              <RoundedIcon
                icon={Search01Icon}
                size={16}
                className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--chat-hollow)]"
              />
              <Input
                id="skill-search"
                aria-label="Search skills"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search skills"
                maxLength={80}
                className="h-10 rounded-full border-[var(--chat-hairline)] bg-[var(--chat-elevated)] pl-9 shadow-none"
              />
            </label>
            <Button
              type="button"
              onClick={() => setEditorSkill(null)}
              className="h-10 rounded-full px-5 shadow-none"
            >
              Create
            </Button>
          </div>
        </header>

        {isLoading && !data ? (
          <LibrarySkeleton />
        ) : error ? (
          <LibraryState
            title="Skills could not be loaded"
            detail="Refresh the page and try again."
          />
        ) : data?.length ? (
          <>
            {!deferredQuery && (
              <section className="mt-10" aria-labelledby="installed-skills">
                <h2
                  id="installed-skills"
                  className="text-sm font-medium text-[var(--chat-mid-ash)]"
                >
                  Installed
                </h2>
                {installedSkills.length ? (
                  <div className="mt-3 flex flex-wrap gap-2">
                    {installedSkills.map((skill) => (
                      <button
                        key={skill.id}
                        type="button"
                        onClick={() => openDetail(skill)}
                        className="flex items-center gap-2 rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-elevated)] py-1.5 pl-1.5 pr-3 text-sm transition-colors hover:bg-[var(--chat-hover)]"
                      >
                        <SkillIcon skill={skill} size="small" />
                        <span>{skill.name}</span>
                      </button>
                    ))}
                  </div>
                ) : (
                  <p className="mt-3 text-sm text-[var(--chat-hollow)]">
                    No skills installed yet.
                  </p>
                )}
              </section>
            )}

            <div className={deferredQuery ? 'mt-10' : 'mt-12'}>
              {groupedSkills.map(
                (category) =>
                  category.skills.length > 0 && (
                    <section
                      key={category.id}
                      className="mb-10"
                      aria-labelledby={`category-${category.id}`}
                    >
                      <h2
                        id={`category-${category.id}`}
                        className="text-sm font-medium text-[var(--chat-mid-ash)]"
                      >
                        {category.label}
                      </h2>
                      <div className="mt-3 grid grid-cols-1 gap-2 md:grid-cols-2 md:gap-x-3">
                        {category.skills.map((skill) => (
                          <SkillCard
                            key={skill.id}
                            skill={skill}
                            busy={
                              isDetailLoading || pendingSkillId === skill.id
                            }
                            onOpen={() => openDetail(skill)}
                            onInstallationChange={(installed) =>
                              changeInstallation(skill, installed)
                            }
                          />
                        ))}
                      </div>
                    </section>
                  ),
              )}
            </div>
          </>
        ) : (
          <LibraryState
            title={deferredQuery ? 'No matching skills' : 'No skills yet'}
            detail={
              deferredQuery
                ? 'Try another search.'
                : 'Create your first personal skill.'
            }
          />
        )}
      </div>

      <SkillDetailDialog
        skill={selectedSkill}
        busy={pendingSkillId === selectedSkill?.id}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedSkill(null);
          }
        }}
        onInstallationChange={(installed) => {
          if (selectedSkill) {
            changeInstallation(selectedSkill, installed);
          }
        }}
        onEdit={() => {
          setEditorSkill(selectedSkill);
          setSelectedSkill(null);
        }}
        onDelete={() => {
          if (selectedSkill) {
            setDeleteSkill(selectedSkill);
          }
        }}
      />

      <SkillEditorDialog
        skill={editorSkill}
        onOpenChange={(open) => {
          if (!open) {
            setEditorSkill(undefined);
          }
        }}
        onSaved={async (saved) => {
          setEditorSkill(undefined);
          await mutate();
          setSelectedSkill(saved);
        }}
        onDelete={(skill) => setDeleteSkill(skill)}
      />

      <AlertDialog
        open={deleteSkill !== null}
        onOpenChange={(open) => {
          if (!open && !pendingSkillId) {
            setDeleteSkill(null);
          }
        }}
      >
        <AlertDialogContent className="rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] text-[var(--chat-ink)]">
          <AlertDialogHeader>
            <AlertDialogTitle>Delete skill?</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteSkill?.name} will be permanently removed from your library
              and future chats.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={pendingSkillId !== null}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              disabled={pendingSkillId !== null}
              onClick={(event) => {
                event.preventDefault();
                deleteCustomSkill();
              }}
              className="bg-red-600 text-white hover:bg-red-500"
            >
              {pendingSkillId ? 'Deleting…' : 'Delete skill'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </main>
  );
}

function SkillCard({
  busy,
  onInstallationChange,
  onOpen,
  skill,
}: {
  busy: boolean;
  onInstallationChange: (installed: boolean) => void;
  onOpen: () => void;
  skill: SkillSummary;
}) {
  return (
    <div className="group flex min-h-[68px] min-w-0 items-center gap-3 rounded-[16px] border border-transparent px-2.5 py-2 transition-colors hover:border-[var(--chat-hairline)] hover:bg-[var(--chat-hover)]">
      <button
        type="button"
        onClick={onOpen}
        className="flex min-w-0 flex-1 items-center gap-3 text-left"
      >
        <SkillIcon skill={skill} />
        <span className="min-w-0">
          <span className="block truncate text-sm font-medium">
            {skill.name}
          </span>
          <span className="mt-0.5 block truncate text-xs text-[var(--chat-hollow)]">
            {skill.description}
          </span>
        </span>
      </button>
      <button
        type="button"
        disabled={busy}
        onClick={() => onInstallationChange(!skill.installed)}
        aria-label={`${skill.installed ? 'Remove' : 'Install'} ${skill.name}`}
        className={cn(
          'flex size-8 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-[var(--chat-elevated)] disabled:opacity-50',
          skill.installed ? 'text-emerald-500' : 'text-[var(--chat-mid-ash)]',
        )}
      >
        <RoundedIcon
          icon={skill.installed ? CheckmarkCircle04Icon : PlusSignIcon}
          size={18}
        />
      </button>
    </div>
  );
}

function SkillIcon({
  skill,
  size = 'default',
}: {
  skill: Pick<SkillSummary, 'icon'>;
  size?: 'default' | 'small';
}) {
  const icon = iconByKey[skill.icon] ?? SparklesIcon;
  return (
    <span
      className={cn(
        'flex shrink-0 items-center justify-center rounded-[11px]',
        size === 'small' ? 'size-7 rounded-full' : 'size-10',
        iconStyleByKey[skill.icon] ?? iconStyleByKey.sparkles,
      )}
    >
      <RoundedIcon icon={icon} size={size === 'small' ? 15 : 20} />
    </span>
  );
}

function SkillDetailDialog({
  busy,
  onDelete,
  onEdit,
  onInstallationChange,
  onOpenChange,
  skill,
}: {
  busy: boolean;
  onDelete: () => void;
  onEdit: () => void;
  onInstallationChange: (installed: boolean) => void;
  onOpenChange: (open: boolean) => void;
  skill: SkillDetail | null;
}) {
  return (
    <Dialog open={skill !== null} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] text-[var(--chat-ink)] shadow-2xl">
        {skill && (
          <>
            <DialogHeader className="pr-8">
              <div className="flex items-center gap-3">
                <SkillIcon skill={skill} />
                <div>
                  <DialogTitle className="text-base">{skill.name}</DialogTitle>
                  <DialogDescription className="mt-1">
                    {skill.source === 'custom'
                      ? 'Your skill'
                      : 'Built-in skill'}
                  </DialogDescription>
                </div>
              </div>
            </DialogHeader>
            <p className="text-sm leading-6 text-[var(--chat-mid-ash)]">
              {skill.description}
            </p>
            <div className="rounded-[14px] bg-[var(--chat-hover)] p-4">
              <p className="text-xs font-semibold uppercase tracking-[0.08em] text-[var(--chat-hollow)]">
                When to use
              </p>
              <p className="mt-2 text-sm leading-6">{skill.whenToUse}</p>
            </div>
            <DialogFooter className="items-center sm:justify-between">
              {skill.source === 'custom' ? (
                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={onDelete}
                    disabled={busy}
                    className="rounded-full text-red-500 hover:text-red-500"
                  >
                    Delete
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={onEdit}
                    disabled={busy}
                    className="rounded-full"
                  >
                    Edit
                  </Button>
                </div>
              ) : (
                <span />
              )}
              <Button
                type="button"
                variant={skill.installed ? 'outline' : 'default'}
                onClick={() => onInstallationChange(!skill.installed)}
                disabled={busy}
                className="rounded-full"
              >
                {busy ? 'Updating…' : skill.installed ? 'Remove' : 'Install'}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function SkillEditorDialog({
  onDelete,
  onOpenChange,
  onSaved,
  skill,
}: {
  onDelete: (skill: SkillDetail) => void;
  onOpenChange: (open: boolean) => void;
  onSaved: (skill: SkillDetail) => Promise<void>;
  skill: SkillDetail | null | undefined;
}) {
  const isOpen = skill !== undefined;
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [form, setForm] = useState<SkillInput>({
    description: '',
    instructions: '',
    name: '',
    whenToUse: '',
  });
  const formKey = skill?.id ?? (skill === null ? 'new' : 'closed');

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (isSubmitting) {
      return;
    }
    const normalized = {
      description: form.description.trim(),
      instructions: form.instructions.trim(),
      name: form.name.trim(),
      whenToUse: form.whenToUse.trim(),
    };
    if (Object.values(normalized).some((value) => !value)) {
      toast.error('Complete every field');
      return;
    }
    setIsSubmitting(true);
    try {
      const response = await fetch(
        skill ? `/app/api/skills/${skill.id}` : '/app/api/skills',
        {
          body: JSON.stringify(normalized),
          headers: { 'Content-Type': 'application/json' },
          method: skill ? 'PATCH' : 'POST',
        },
      );
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error || 'Skill could not be saved');
      }
      await onSaved(payload);
      toast.success(skill ? 'Skill updated' : 'Skill created');
    } catch (saveError) {
      toast.error(
        saveError instanceof Error
          ? saveError.message
          : 'Skill could not be saved',
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent
        key={formKey}
        className="max-h-[90svh] max-w-xl overflow-y-auto rounded-[18px] border-[var(--chat-hairline)] bg-[var(--chat-elevated)] text-[var(--chat-ink)] shadow-2xl"
        onOpenAutoFocus={() => {
          setForm({
            description: skill?.description ?? '',
            instructions: skill?.instructions ?? '',
            name: skill?.name ?? '',
            whenToUse: skill?.whenToUse ?? '',
          });
        }}
      >
        <DialogHeader>
          <DialogTitle className="text-base">
            {skill ? 'Edit skill' : 'Create skill'}
          </DialogTitle>
          <DialogDescription>
            Personal skills guide Teya but cannot add tools or permissions.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          <SkillField
            id="skill-name"
            label="Name"
            value={form.name}
            maxLength={80}
            onChange={(name) => setForm((current) => ({ ...current, name }))}
          />
          <SkillField
            id="skill-description"
            label="Description"
            value={form.description}
            maxLength={240}
            onChange={(description) =>
              setForm((current) => ({ ...current, description }))
            }
          />
          <SkillField
            id="skill-when-to-use"
            label="When to use"
            value={form.whenToUse}
            maxLength={500}
            multiline
            onChange={(whenToUse) =>
              setForm((current) => ({ ...current, whenToUse }))
            }
          />
          <SkillField
            id="skill-instructions"
            label="Instructions"
            value={form.instructions}
            maxLength={8000}
            multiline
            tall
            onChange={(instructions) =>
              setForm((current) => ({ ...current, instructions }))
            }
          />
          <DialogFooter className="items-center sm:justify-between">
            {skill ? (
              <Button
                type="button"
                variant="ghost"
                onClick={() => onDelete(skill)}
                disabled={isSubmitting}
                className="rounded-full text-red-500 hover:text-red-500"
              >
                Delete
              </Button>
            ) : (
              <span />
            )}
            <div className="flex justify-end gap-2">
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
                disabled={isSubmitting}
                className="rounded-full"
              >
                {isSubmitting ? 'Saving…' : skill ? 'Save' : 'Create skill'}
              </Button>
            </div>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function SkillField({
  id,
  label,
  maxLength,
  multiline = false,
  onChange,
  tall = false,
  value,
}: {
  id: string;
  label: string;
  maxLength: number;
  multiline?: boolean;
  onChange: (value: string) => void;
  tall?: boolean;
  value: string;
}) {
  return (
    <div>
      <div className="flex items-center justify-between gap-3">
        <label htmlFor={id} className="text-sm font-medium">
          {label}
        </label>
        <span className="text-xs text-[var(--chat-hollow)]">
          {value.length}/{maxLength}
        </span>
      </div>
      {multiline ? (
        <Textarea
          id={id}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          maxLength={maxLength}
          required
          className={cn(
            'mt-2 resize-none rounded-[12px] border-[var(--chat-hairline)] bg-transparent shadow-none focus-visible:ring-1 focus-visible:ring-ring',
            tall ? 'min-h-40' : 'min-h-24',
          )}
        />
      ) : (
        <Input
          id={id}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          maxLength={maxLength}
          required
          className="mt-2 h-10 rounded-[12px] border-[var(--chat-hairline)] bg-transparent shadow-none"
        />
      )}
    </div>
  );
}

function LibrarySkeleton() {
  return (
    <div className="mt-10 space-y-10">
      {[0, 1, 2].map((section) => (
        <div key={section}>
          <div className="h-4 w-24 animate-pulse rounded bg-[var(--chat-hover)]" />
          <div className="mt-3 grid gap-2 md:grid-cols-2">
            {[0, 1, 2, 3].map((item) => (
              <div
                key={item}
                className="h-[68px] animate-pulse rounded-[16px] bg-[var(--chat-hover)]"
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function LibraryState({ detail, title }: { detail: string; title: string }) {
  return (
    <div className="flex min-h-[420px] flex-col items-center justify-center text-center">
      <div className="flex size-14 items-center justify-center rounded-2xl bg-[var(--chat-hover)]">
        <RoundedIcon icon={SparklesIcon} size={27} />
      </div>
      <h2 className="mt-4 text-base font-medium">{title}</h2>
      <p className="mt-1 text-sm text-[var(--chat-hollow)]">{detail}</p>
    </div>
  );
}
