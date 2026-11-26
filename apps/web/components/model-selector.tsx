'use client';

import {
  CheckmarkCircle02Icon,
  ChevronDownIcon,
} from '@hugeicons/core-free-icons';
import React, { useEffect, useMemo, useState } from 'react';

import { saveChatModelAsCookie } from '@/app/(chat)/actions';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import { chatModels } from '@/lib/ai/models';
import { cn } from '@/lib/utils';

function splitModelName(name: string): { base: string; version: string } {
  const match = name.match(/^(Teya)(?:\s+)(v.*)$/i);
  if (match) {
    return { base: match[1], version: match[2] };
  }

  const fallback = name.match(/^([^\d]+)(.*)$/);
  if (fallback) {
    return { base: fallback[1].trim(), version: fallback[2].trim() };
  }
  return { base: name, version: '' };
}

function AnimatedVersion({ version }: { version: string }) {
  const [displayed, setDisplayed] = useState(version);
  const [fade, setFade] = useState(false);

  useEffect(() => {
    if (displayed !== version) {
      setFade(true);
      const timeout1 = setTimeout(() => {
        setDisplayed(version);
        setFade(false);
      }, 120);
      return () => clearTimeout(timeout1);
    }
  }, [version, displayed]);

  return (
    <span
      className={cn(
        'transition-opacity duration-200',
        fade ? 'opacity-0' : 'opacity-100',
      )}
      style={{ display: 'inline-block' }}
    >
      {displayed}
    </span>
  );
}

export function ModelSelector({
  selectedModelId,
  onModelChange,
  className,
}: {
  selectedModelId: string;
  onModelChange: (modelId: string) => void;
} & React.ComponentProps<typeof Button>) {
  const [open, setOpen] = useState(false);

  const selectedChatModel = useMemo(
    () => chatModels.find((chatModel) => chatModel.id === selectedModelId),
    [selectedModelId],
  );

  const { base, version } = selectedChatModel
    ? splitModelName(selectedChatModel.name)
    : { base: '', version: '' };

  return (
    <>
      <DropdownMenu open={open} onOpenChange={setOpen}>
        <DropdownMenuTrigger
          asChild
          className={cn(
            'w-fit data-[state=open]:bg-[var(--chat-hover)] data-[state=open]:text-[var(--chat-ink)]',
            className,
          )}
        >
          <Button
            data-testid="model-selector"
            variant="ghost"
            className="h-8 rounded-[10px] px-2.5 text-sm font-semibold text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-3.5"
          >
            <span>
              {base}
              {version && ' '}
              <AnimatedVersion version={version} />
            </span>
            <RoundedIcon icon={ChevronDownIcon} size={14} />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="start"
          className="min-w-[280px] rounded-[10px] border-border bg-popover p-1 text-popover-foreground shadow-none"
        >
          <div className="flex select-none items-center justify-between px-3 py-2 text-xs font-medium text-muted-foreground">
            <span>Model</span>
          </div>
          {chatModels.map((chatModel) => {
            const { id } = chatModel;
            const { base: itemBase, version: itemVersion } = splitModelName(
              chatModel.name,
            );

            return (
              <DropdownMenuItem
                data-testid={`model-selector-item-${id}`}
                key={id}
                onSelect={() => {
                  setOpen(false);
                  onModelChange(id);
                  void saveChatModelAsCookie(id);
                }}
                data-active={id === selectedModelId}
                asChild
              >
                <button
                  type="button"
                  className="group/item flex w-full flex-row items-center justify-between gap-4 rounded-lg px-2 py-1.5 hover:bg-accent"
                >
                  <div className="flex flex-col gap-1 items-start">
                    <div>
                      {itemBase}
                      {itemVersion && ' '}
                      <span className="font-medium">{itemVersion}</span>
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {chatModel.description}
                    </div>
                  </div>

                  <div className="text-foreground opacity-0 group-data-[active=true]/item:opacity-100">
                    <RoundedIcon icon={CheckmarkCircle02Icon} size={18} />
                  </div>
                </button>
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}
