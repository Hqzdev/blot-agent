'use client';

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { type Hotkey, formatHotkey } from '@/hooks/use-hotkeys';
import { useIsMobile } from '@/hooks/use-mobile';
import { useOS } from '@/hooks/use-os';

interface Shortcut {
  label: string;
  hotkey: Hotkey;
  description?: string;
}

interface KeyboardShortcutsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const SHORTCUTS: Shortcut[] = [
  {
    label: 'Отправить сообщение',
    hotkey: { key: 'Enter' },
    description: 'Отправить текущее сообщение',
  },
  {
    label: 'Новая строка',
    hotkey: { key: 'Enter', shift: true },
    description: 'Добавить новую строку в сообщении',
  },
  {
    label: 'Поиск чатов',
    hotkey: { key: 'k', meta: true },
    description: 'Открыть поиск по чатам',
  },
  {
    label: 'Фокус на поле ввода',
    hotkey: { key: 'l', meta: true },
    description: 'Установить фокус на поле ввода сообщения',
  },
  {
    label: 'Показать горячие клавиши',
    hotkey: { key: '/', meta: true },
    description: 'Открыть этот диалог',
  },
  {
    label: 'Закрыть диалог',
    hotkey: { key: 'Escape' },
    description: 'Закрыть открытый диалог',
  },
];

export function KeyboardShortcutsDialog({
  open,
  onOpenChange,
}: KeyboardShortcutsDialogProps) {
  const os = useOS();
  const isMobile = useIsMobile();

  if (isMobile) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[80vh] max-w-2xl overflow-y-auto rounded-[10px] border-border bg-background text-foreground shadow-none">
        <DialogHeader>
          <DialogTitle className="text-xl font-medium">
            Горячие клавиши
          </DialogTitle>
        </DialogHeader>
        <div className="mt-4 space-y-4">
          {SHORTCUTS.map((shortcut) => {
            const formatted = formatHotkey(shortcut.hotkey, os);
            return (
              <div
                key={shortcut.label}
                className="flex items-center justify-between border-b border-border py-2 last:border-0"
              >
                <div className="flex-1">
                  <div className="font-medium">{shortcut.label}</div>
                  {shortcut.description && (
                    <div className="mt-0.5 text-sm text-muted-foreground">
                      {shortcut.description}
                    </div>
                  )}
                </div>
                <kbd className="inline-flex items-center gap-1 rounded-lg border border-border bg-muted px-2.5 py-1.5 text-sm font-medium text-muted-foreground">
                  {formatted}
                </kbd>
              </div>
            );
          })}
        </div>
        <div className="mt-6 border-t border-border pt-4">
          <p className="text-sm text-muted-foreground">
            Горячие клавиши доступны только на десктопе. На мобильных
            устройствах они отключены.
          </p>
        </div>
      </DialogContent>
    </Dialog>
  );
}
