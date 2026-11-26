'use client';

import { Button } from '@/components/ui/button';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import {
  ComputerIcon,
  Moon02Icon,
  PaintBoardIcon,
  SecurityCheckIcon,
  Sun03Icon,
  Tick02Icon,
  UserIcon,
} from '@hugeicons/core-free-icons';
import { Mail, Menu, Pencil, User as UserDataIcon, X } from 'lucide-react';
import { signOut, useSession } from 'next-auth/react';
import { useTheme } from 'next-themes';
import { useEffect, useState } from 'react';
import { EditNicknameDialog } from './edit-nickname-dialog';

export type SettingsSection = 'appearance' | 'security' | 'account';

const themeOptions = [
  {
    id: 'system',
    label: 'System',
    description: 'Use your device setting',
    icon: ComputerIcon,
  },
  {
    id: 'light',
    label: 'Light',
    description: 'Always use light mode',
    icon: Sun03Icon,
  },
  {
    id: 'dark',
    label: 'Dark',
    description: 'Always use dark mode',
    icon: Moon02Icon,
  },
] as const;

interface SettingsDialogProps {
  initialSection?: SettingsSection;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export default function SettingsDialog(props: SettingsDialogProps) {
  const [activeSection, setActiveSection] = useState<SettingsSection>(
    props.initialSection ?? 'security',
  );
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const isControlled =
    typeof props.open === 'boolean' && typeof props.onOpenChange === 'function';
  const [internalOpen, setInternalOpen] = useState(false);
  const isOpen = isControlled ? props.open : internalOpen;
  const setIsOpen = isControlled
    ? (open: boolean) => {
        if (props.onOpenChange) props.onOpenChange(open);
      }
    : setInternalOpen;

  useEffect(() => {
    if (isOpen) {
      setActiveSection(props.initialSection ?? 'security');
      setIsMobileMenuOpen(false);
    }
  }, [isOpen, props.initialSection]);

  const sidebarItems = [
    {
      id: 'appearance' as const,
      label: 'Appearance',
      icon: PaintBoardIcon,
    },
    {
      id: 'security' as const,
      label: 'Security',
      icon: SecurityCheckIcon,
    },
    { id: 'account' as const, label: 'Account', icon: UserIcon },
  ];

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-0 md:p-4">
      {isMobileMenuOpen && (
        <div
          className="fixed inset-0 z-[45] bg-black/50 md:hidden"
          onClick={() => setIsMobileMenuOpen(false)}
        />
      )}

      <div className="relative z-50 flex size-full flex-col overflow-hidden border border-[var(--chat-hairline)] bg-[var(--chat-paper)] text-[var(--chat-ink)] md:h-[90vh] md:max-w-6xl md:flex-row md:rounded-[10px]">
        <div className="z-50 flex items-center justify-between border-b border-[var(--chat-hairline)] bg-[var(--chat-paper)] p-4 md:hidden">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="size-9 rounded-[10px] hover:bg-[var(--chat-hover)]"
          >
            <Menu className="h-5 w-5" />
          </Button>
          <h2 className="text-base font-medium">Settings</h2>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setIsOpen(false)}
            className="size-9 rounded-[10px] hover:bg-[var(--chat-hover)]"
          >
            <X className="h-5 w-5" />
          </Button>
        </div>

        <div
          className={`${
            isMobileMenuOpen ? 'block' : 'hidden'
          } absolute inset-0 z-[60] flex w-full flex-col border-r border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] md:relative md:inset-auto md:z-auto md:block md:w-64`}
        >
          <div className="border-b border-[var(--chat-hairline)] p-4">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-base font-medium md:hidden">Settings</h2>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  setIsOpen(false);
                  setIsMobileMenuOpen(false);
                }}
                className="size-8 rounded-[10px] hover:bg-[var(--chat-hover)] md:ml-auto"
              >
                <X className="h-5 w-5" />
              </Button>
            </div>
          </div>

          <nav className="flex-1 space-y-1 overflow-y-auto p-3">
            {sidebarItems.map((item) => {
              const isActive = activeSection === item.id;

              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => {
                    setActiveSection(item.id);
                    setIsMobileMenuOpen(false);
                  }}
                  className={`flex w-full items-center gap-3 rounded-[10px] px-3 py-2 text-left text-sm transition-colors ${
                    isActive
                      ? 'bg-[var(--chat-hover)]'
                      : 'hover:bg-[var(--chat-hover)]'
                  }`}
                >
                  <RoundedIcon
                    icon={item.icon}
                    size={17}
                    className="text-[var(--chat-mid-ash)]"
                  />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </nav>
        </div>

        <div className="flex-1 overflow-y-auto bg-[var(--chat-paper)]">
          <div className="p-4 md:p-8 max-w-4xl">
            {activeSection === 'appearance' && <AppearanceSettings />}
            {activeSection === 'security' && <SecuritySettings />}
            {activeSection === 'account' && <AccountSettings />}
          </div>
        </div>
      </div>
    </div>
  );
}

function AppearanceSettings() {
  const { theme, setTheme } = useTheme();
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
  }, []);

  const selectedTheme = isMounted ? theme || 'system' : 'system';

  return (
    <div className="space-y-6 md:space-y-8">
      <div>
        <h3 className="mb-2 text-xl font-medium text-[var(--chat-ink)] md:text-2xl">
          Appearance
        </h3>
        <div className="mb-4 h-px bg-[var(--chat-hairline)] md:mb-8" />
      </div>

      <div className="space-y-3">
        <div>
          <h4 className="text-base font-medium text-[var(--chat-ink)] md:text-lg">
            Theme
          </h4>
          <p className="mt-1 text-sm text-[var(--chat-mid-ash)]">
            Choose how Teya looks on this device.
          </p>
        </div>

        <div className="grid gap-3 md:grid-cols-3">
          {themeOptions.map((option) => {
            const isSelected = selectedTheme === option.id;

            return (
              <button
                key={option.id}
                type="button"
                disabled={!isMounted}
                aria-pressed={isSelected}
                onClick={() => setTheme(option.id)}
                className={`relative flex min-h-28 flex-col items-start rounded-[14px] border p-4 text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[var(--chat-ink)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--chat-paper)] ${
                  isSelected
                    ? 'border-[var(--chat-ink)] bg-[var(--chat-hover)]'
                    : 'border-[var(--chat-hairline)] bg-[var(--chat-paper)] hover:bg-[var(--chat-hover)]'
                } disabled:cursor-wait`}
              >
                <div className="mb-5 flex size-9 items-center justify-center rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-paper)]">
                  <RoundedIcon icon={option.icon} size={18} />
                </div>
                <span className="text-sm font-medium text-[var(--chat-ink)]">
                  {option.label}
                </span>
                <span className="mt-0.5 text-xs text-[var(--chat-mid-ash)]">
                  {option.description}
                </span>
                {isSelected && (
                  <span className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-[var(--chat-ink)] text-[var(--chat-paper)]">
                    <RoundedIcon icon={Tick02Icon} size={13} strokeWidth={2} />
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function SecuritySettings() {
  const { data: session } = useSession();
  const [userData, setUserData] = useState<{
    nickname: string;
    email: string;
  } | null>(null);
  const [isEditNicknameOpen, setIsEditNicknameOpen] = useState(false);

  useEffect(() => {
    if (session?.user) {
      fetch('/app/api/user-profile')
        .then((res) => res.json())
        .then((data) => {
          setUserData({
            nickname: session.user?.nickname || '',
            email: data.email || session.user?.email || '',
          });
        })
        .catch(() => {
          setUserData({
            nickname: session.user?.nickname || '',
            email: session.user?.email || '',
          });
        });
    }
  }, [session]);

  const handleLogout = () => {
    signOut({ redirect: true, callbackUrl: '/app/login?loggedOut=1' });
  };

  return (
    <>
      <div className="space-y-4 md:space-y-8">
        <div>
          <h3 className="mb-2 text-xl font-medium text-[var(--chat-ink)] md:text-2xl">
            Security
          </h3>
          <div className="mb-4 h-px bg-[var(--chat-hairline)] md:mb-8" />
        </div>

        <div className="space-y-4">
          <h4 className="text-base font-medium text-[var(--chat-ink)] md:text-lg">
            Данные пользователя
          </h4>

          <div className="flex flex-col gap-2 rounded-lg border border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] p-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
            <div className="flex items-center gap-3 flex-1 min-w-0">
              <div className="flex size-8 flex-shrink-0 items-center justify-center rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-paper)]">
                <UserDataIcon className="size-4 text-[var(--chat-mid-ash)]" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="mb-1 text-xs text-[var(--chat-mid-ash)]">
                  Имя пользователя
                </p>
                <p className="truncate text-sm font-medium text-[var(--chat-ink)]">
                  {userData?.nickname || session?.user?.nickname || '—'}
                </p>
              </div>
            </div>
            <Button
              variant="outline"
              size="sm"
              className="h-9 flex-shrink-0 rounded-full border-[var(--chat-hairline)] bg-[var(--chat-paper)] px-3 text-[var(--chat-ink)] hover:bg-[var(--chat-hover)]"
              onClick={() => setIsEditNicknameOpen(true)}
            >
              <Pencil className="w-4 h-4 mr-2" />
              Изменить
            </Button>
          </div>

          <div className="flex flex-col gap-2 rounded-lg border border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] p-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
            <div className="flex items-center gap-3 flex-1 min-w-0">
              <div className="flex size-8 flex-shrink-0 items-center justify-center rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-paper)]">
                <Mail className="size-4 text-[var(--chat-mid-ash)]" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="mb-1 text-xs text-[var(--chat-mid-ash)]">
                  Электронная почта
                </p>
                <p className="truncate text-sm font-medium text-[var(--chat-ink)]">
                  {userData?.email || session?.user?.email || '—'}
                </p>
              </div>
            </div>
            <div className="flex-shrink-0 text-xs text-[var(--chat-mid-ash)]">
              Нельзя изменить
            </div>
          </div>
        </div>

        <div className="space-y-4 border-t border-[var(--chat-hairline)] pt-4 md:space-y-8">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 sm:gap-0">
            <span className="text-sm text-[var(--chat-ink)] md:text-base">
              Log out of this device
            </span>
            <Button
              variant="outline"
              size="sm"
              className="h-9 w-full rounded-full border-[var(--chat-hairline)] bg-[var(--chat-paper)] px-4 text-[var(--chat-ink)] hover:bg-[var(--chat-hover)] sm:w-auto"
              onClick={handleLogout}
            >
              Log out
            </Button>
          </div>
        </div>
      </div>

      <EditNicknameDialog
        open={isEditNicknameOpen}
        onOpenChange={setIsEditNicknameOpen}
        currentNickname={userData?.nickname || session?.user?.nickname || ''}
      />
    </>
  );
}

function AccountSettings() {
  return (
    <div className="space-y-4">
      <h3 className="text-xl font-medium text-[var(--chat-ink)]">
        Аккаунт Ori
      </h3>
      <p className="text-sm text-[var(--chat-mid-ash)]">
        Веб-приложение использует ваш общий аккаунт Ori. Вход доступен по коду
        из письма, через Google или Яндекс. Управление паролем и удаление общего
        аккаунта доступны в профиле Ori на Mac или iPhone.
      </p>
    </div>
  );
}
