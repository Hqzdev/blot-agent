'use client';

import {
  AccountSetting01Icon,
  ArrowRight01Icon,
  HelpCircleIcon,
  KeyboardIcon,
  Logout01Icon,
  Profile02Icon,
  Settings01Icon,
  SparklesIcon,
} from '@hugeicons/core-free-icons';
import type { User } from 'next-auth';
import Form from 'next/form';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { useState } from 'react';

import { signOutAction } from '@/app/actions/sign-out';
import { CustomizeTeyaDialog } from '@/components/customize-teya-dialog';
import { KeyboardShortcutsDialog } from '@/components/keyboard-shortcuts-dialog';
import SettingsDialog, {
  type SettingsSection,
} from '@/components/settings-dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import { UpgradePlanDialog } from '@/components/upgrade-plan-dialog';

interface ProfileMenuProps {
  align?: 'start' | 'center' | 'end';
  children: ReactNode;
  side?: 'top' | 'right' | 'bottom' | 'left';
  user: User;
}

const menuItemClassName =
  'h-9 cursor-pointer gap-2.5 rounded-[11px] px-2.5 text-sm font-normal text-popover-foreground focus:bg-accent focus:text-accent-foreground';

export function ProfileMenu({
  align = 'end',
  children,
  side = 'bottom',
  user,
}: ProfileMenuProps) {
  const [isCustomizeOpen, setIsCustomizeOpen] = useState(false);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isShortcutsOpen, setIsShortcutsOpen] = useState(false);
  const [isUpgradeOpen, setIsUpgradeOpen] = useState(false);
  const [settingsSection, setSettingsSection] =
    useState<SettingsSection>('security');
  const displayName = (
    user.nickname ||
    user.name ||
    user.email ||
    'Teya user'
  ).trim();
  const initials = displayName.slice(0, 2).toUpperCase();
  const plan = user.subscription || 'free';
  const planLabel = plan.charAt(0).toUpperCase() + plan.slice(1);

  const openSettings = (section: SettingsSection) => {
    setSettingsSection(section);
    setIsSettingsOpen(true);
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>{children}</DropdownMenuTrigger>
        <DropdownMenuContent
          align={align}
          side={side}
          sideOffset={8}
          collisionPadding={8}
          className="w-[32rem] max-w-[calc(100vw-1rem)] rounded-[20px] border border-border bg-popover p-2 text-popover-foreground shadow-[0_16px_45px_rgba(0,0,0,0.2)]"
        >
          <DropdownMenuItem
            className="h-auto cursor-pointer rounded-[12px] px-2.5 py-1.5 focus:bg-accent"
            onSelect={() => openSettings('security')}
          >
            <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[#4a9df8] text-xs font-semibold text-white">
              {initials}
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate text-sm font-medium leading-5">
                {displayName}
              </span>
              <span className="text-xs leading-4 text-muted-foreground">
                {planLabel}
              </span>
            </span>
            <RoundedIcon icon={ArrowRight01Icon} size={17} strokeWidth={1.8} />
          </DropdownMenuItem>

          <DropdownMenuSeparator className="mx-2 my-1.5 bg-border" />

          <DropdownMenuItem
            className={menuItemClassName}
            onSelect={() => setIsUpgradeOpen(true)}
          >
            <RoundedIcon icon={SparklesIcon} size={18} strokeWidth={1.8} />
            <span>Использование и подписка</span>
          </DropdownMenuItem>
          <DropdownMenuItem
            className={menuItemClassName}
            onSelect={() => setIsCustomizeOpen(true)}
          >
            <RoundedIcon
              icon={AccountSetting01Icon}
              size={18}
              strokeWidth={1.8}
            />
            <span>Personalization</span>
          </DropdownMenuItem>
          <DropdownMenuItem
            className={menuItemClassName}
            onSelect={() => openSettings('security')}
          >
            <RoundedIcon icon={Profile02Icon} size={18} strokeWidth={1.8} />
            <span>Profile</span>
          </DropdownMenuItem>
          <DropdownMenuItem
            className={menuItemClassName}
            onSelect={() => openSettings('appearance')}
          >
            <RoundedIcon icon={Settings01Icon} size={18} strokeWidth={1.8} />
            <span>Settings</span>
          </DropdownMenuItem>

          <DropdownMenuSeparator className="mx-2 my-1.5 bg-border" />

          <DropdownMenuSub>
            <DropdownMenuSubTrigger className={menuItemClassName}>
              <RoundedIcon icon={HelpCircleIcon} size={18} strokeWidth={1.8} />
              <span>Help</span>
              <RoundedIcon
                icon={ArrowRight01Icon}
                className="ml-auto"
                size={17}
                strokeWidth={1.8}
              />
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent className="min-w-52 rounded-[16px] border-border bg-popover p-1.5 shadow-[0_14px_40px_rgba(0,0,0,0.18)]">
              <DropdownMenuItem
                className="h-9 cursor-pointer rounded-[10px] px-2.5 text-sm focus:bg-accent"
                onSelect={() => setIsShortcutsOpen(true)}
              >
                <RoundedIcon icon={KeyboardIcon} size={18} />
                Keyboard shortcuts
              </DropdownMenuItem>
              <DropdownMenuItem
                asChild
                className="h-9 cursor-pointer rounded-[10px] px-2.5 text-sm focus:bg-accent"
              >
                <Link href="/privacy">Privacy policy</Link>
              </DropdownMenuItem>
              <DropdownMenuItem
                asChild
                className="h-9 cursor-pointer rounded-[10px] px-2.5 text-sm focus:bg-accent"
              >
                <Link href="/policy">Terms of use</Link>
              </DropdownMenuItem>
            </DropdownMenuSubContent>
          </DropdownMenuSub>

          <Form action={signOutAction}>
            <DropdownMenuItem asChild className={menuItemClassName}>
              <button type="submit" className="w-full">
                <RoundedIcon icon={Logout01Icon} size={18} strokeWidth={1.8} />
                <span>Log out</span>
              </button>
            </DropdownMenuItem>
          </Form>
        </DropdownMenuContent>
      </DropdownMenu>

      <SettingsDialog
        initialSection={settingsSection}
        open={isSettingsOpen}
        onOpenChange={setIsSettingsOpen}
      />
      <UpgradePlanDialog open={isUpgradeOpen} onOpenChange={setIsUpgradeOpen} />
      <CustomizeTeyaDialog
        open={isCustomizeOpen}
        onOpenChange={setIsCustomizeOpen}
      />
      <KeyboardShortcutsDialog
        open={isShortcutsOpen}
        onOpenChange={setIsShortcutsOpen}
      />
    </>
  );
}
