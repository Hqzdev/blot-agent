'use client';

import { type Hotkey, formatHotkey } from '@/hooks/use-hotkeys';
import { useOS } from '@/hooks/use-os';

interface HotkeyBadgeProps {
  hotkey: Hotkey;
  className?: string;
}

export function HotkeyBadge({ hotkey, className = '' }: HotkeyBadgeProps) {
  const os = useOS();
  const formatted = formatHotkey(hotkey, os);

  return (
    <kbd
      className={`inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded ${className}`}
    >
      {formatted}
    </kbd>
  );
}
