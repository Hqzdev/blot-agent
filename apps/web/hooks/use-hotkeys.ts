import { useEffect, useRef } from 'react';
import { useIsMobile } from './use-mobile';
import type { OS } from './use-os';

export type Hotkey = {
  key: string;
  meta?: boolean;
  shift?: boolean;
  alt?: boolean;
  ctrl?: boolean;
};

export type HotkeyHandler = (event: KeyboardEvent) => void;

export function useHotkeys(
  hotkey: Hotkey | Hotkey[],
  handler: HotkeyHandler,
  options?: {
    enabled?: boolean;
    os?: OS;
  },
) {
  const isMobile = useIsMobile();
  const handlerRef = useRef(handler);
  const enabled = options?.enabled !== false;

  useEffect(() => {
    handlerRef.current = handler;
  }, [handler]);

  useEffect(() => {
    if (isMobile || !enabled) return;

    const hotkeys = Array.isArray(hotkey) ? hotkey : [hotkey];
    const isMac =
      options?.os === 'mac' ||
      (!options?.os &&
        typeof navigator !== 'undefined' &&
        /Mac|iPhone|iPod|iPad/i.test(navigator.platform));

    const handleKeyDown = (event: KeyboardEvent) => {
      for (const hk of hotkeys) {
        const keyMatches =
          event.key.toLowerCase() === hk.key.toLowerCase() ||
          event.code.toLowerCase() === hk.key.toLowerCase();

        if (!keyMatches) continue;

        let metaMatches = true;
        if (hk.meta !== undefined) {
          if (isMac) {
            metaMatches = event.metaKey === hk.meta;
          } else {
            metaMatches = event.ctrlKey === hk.meta;
          }
        }

        const ctrlMatches =
          hk.ctrl !== undefined ? event.ctrlKey === hk.ctrl : true;
        const shiftMatches =
          hk.shift !== undefined ? event.shiftKey === hk.shift : true;
        const altMatches =
          hk.alt !== undefined ? event.altKey === hk.alt : true;

        if (metaMatches && ctrlMatches && shiftMatches && altMatches) {
          event.preventDefault();
          event.stopPropagation();
          handlerRef.current(event);
          break;
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [hotkey, isMobile, enabled, options?.os]);
}

export function formatHotkey(hotkey: Hotkey, os?: OS): string {
  const isMac =
    os === 'mac' ||
    (!os &&
      typeof navigator !== 'undefined' &&
      /Mac|iPhone|iPod|iPad/i.test(navigator.platform));
  const parts: string[] = [];

  if (hotkey.meta) {
    parts.push(isMac ? '⌘' : 'Ctrl');
  }
  if (hotkey.ctrl && !hotkey.meta) {
    parts.push('Ctrl');
  }
  if (hotkey.shift) {
    parts.push('Shift');
  }
  if (hotkey.alt) {
    parts.push(isMac ? '⌥' : 'Alt');
  }

  let key = hotkey.key;
  if (key === ' ') key = 'Space';
  else if (key.length === 1) key = key.toUpperCase();
  else key = key.charAt(0).toUpperCase() + key.slice(1).toLowerCase();

  parts.push(key);

  return parts.join(isMac ? ' ' : ' + ');
}
