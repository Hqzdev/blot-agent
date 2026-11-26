'use client';

import type { User } from 'next-auth';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';

import { ProfileMenu } from '@/components/profile-menu';
import { SidebarHistory } from '@/components/sidebar-history';
import { SidebarUserNav } from '@/components/sidebar-user-nav';
import { TeyaLogo } from '@/components/teya-logo';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { useHotkeys } from '@/hooks/use-hotkeys';
import { useOS } from '@/hooks/use-os';
import type { ChatSummary } from '@/lib/db/schema';
import { fetcher } from '@/lib/utils';
import {
  BubbleChatIcon,
  ComputerProgramming01Icon,
  Folder02Icon,
  Image01Icon,
  LibraryIcon,
  MessageAdd01Icon,
  PanelLeftCloseIcon,
  PanelLeftOpenIcon,
  Plug01Icon,
  Search01Icon,
  UserCircleIcon,
} from '@hugeicons/core-free-icons';
import type { IconSvgElement } from '@hugeicons/react';
import { useMemo, useState } from 'react';
import useSWR from 'swr';
import { HotkeyBadge } from './hotkey-badge';

type DisabledNavigationItem = {
  label: string;
  icon: IconSvgElement;
  badge?: string;
};

const pilotNavigationItem: DisabledNavigationItem = {
  label: 'Pilot',
  icon: ComputerProgramming01Icon,
  badge: 'Soon',
};

export function AppSidebar({ user }: { user: User | undefined }) {
  const router = useRouter();
  const pathname = usePathname();
  const { isMobile, setOpen, setOpenMobile, state } = useSidebar();
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isSidebarHovered, setIsSidebarHovered] = useState(false);
  const os = useOS();
  const isRail = state === 'collapsed' && !isMobile;
  const initials = (user?.nickname || user?.email || 'L')
    .trim()
    .slice(0, 2)
    .toUpperCase();

  useHotkeys(
    { key: 'k', meta: true },
    (e) => {
      if (user) {
        e.preventDefault();
        setIsSearchOpen(true);
      }
    },
    { os, enabled: !!user },
  );

  const handleNewChatClick = (e: React.MouseEvent) => {
    e.preventDefault();
    setOpenMobile(false);
    router.push('/chat');
    router.refresh();
  };

  return (
    <Sidebar
      collapsible="icon"
      className="border-r border-[var(--chat-hairline)] bg-[var(--chat-paper)]"
      onMouseEnter={() => setIsSidebarHovered(true)}
      onMouseLeave={() => setIsSidebarHovered(false)}
    >
      <div className="relative min-h-0 flex-1 overflow-hidden">
        <div
          aria-hidden={!isRail}
          className={`absolute inset-y-0 left-0 hidden w-[--sidebar-width-icon] transition-[visibility] duration-0 md:block ${
            isRail ? 'visible delay-0' : 'invisible delay-200'
          }`}
        >
          <div
            className={`flex h-full w-full flex-col bg-[var(--chat-paper)] transition-[opacity,transform] duration-200 ease-linear ${
              isRail
                ? 'translate-x-0 opacity-100'
                : 'pointer-events-none -translate-x-1 opacity-0'
            }`}
          >
            <SidebarHeader className="shrink-0 items-center gap-2 bg-[var(--chat-paper)] px-0 pb-0 pt-3">
              <RailButton label="Open sidebar" onClick={() => setOpen(true)}>
                <span className="relative flex size-5 items-center justify-center">
                  <span
                    className={`absolute flex transition-opacity duration-150 ${
                      isSidebarHovered ? 'opacity-0' : 'opacity-100'
                    }`}
                  >
                    <TeyaLogo size={19} priority />
                  </span>
                  <RoundedIcon
                    icon={PanelLeftOpenIcon}
                    className={`absolute transition-opacity duration-150 ${
                      isSidebarHovered ? 'opacity-100' : 'opacity-0'
                    }`}
                  />
                </span>
              </RailButton>
              <div className="mt-1">
                <RailButton label="New chat" onClick={handleNewChatClick}>
                  <RoundedIcon icon={MessageAdd01Icon} />
                </RailButton>
              </div>
              <RailButton
                label="Search chats"
                onClick={() => setIsSearchOpen(true)}
              >
                <RoundedIcon icon={Search01Icon} />
              </RailButton>
              <RailButton label="Chat history" onClick={() => setOpen(true)}>
                <RoundedIcon icon={BubbleChatIcon} />
              </RailButton>
            </SidebarHeader>
            <SidebarContent className="bg-[var(--chat-paper)]" />
            <SidebarFooter className="shrink-0 items-center border-0 bg-[var(--chat-paper)] p-0 pb-4">
              {user ? (
                <ProfileMenu user={user} align="end" side="right">
                  <button
                    type="button"
                    className="flex size-7 items-center justify-center rounded-full bg-[#4a9df8] text-[11px] font-semibold text-white transition-transform hover:scale-105"
                    aria-label="Open profile menu"
                    title={user.nickname || user.email || 'Profile'}
                  >
                    {initials}
                  </button>
                </ProfileMenu>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Link
                      href="/login"
                      className="flex size-7 items-center justify-center rounded-full bg-[#4a9df8] text-white"
                      aria-label="Log in"
                    >
                      <RoundedIcon icon={UserCircleIcon} size={16} />
                    </Link>
                  </TooltipTrigger>
                  <TooltipContent side="right">Log in</TooltipContent>
                </Tooltip>
              )}
            </SidebarFooter>
          </div>
        </div>
        <div
          aria-hidden={isRail}
          className={`absolute inset-y-0 left-0 w-[--sidebar-width] transition-[visibility] duration-0 ${
            isRail ? 'invisible delay-200' : 'visible delay-0'
          }`}
        >
          <div
            className={`flex h-full w-full flex-col bg-[var(--chat-sidebar-mist)] transition-[opacity,transform] duration-200 ease-linear ${
              isRail
                ? 'pointer-events-none -translate-x-3 opacity-0'
                : 'translate-x-0 opacity-100'
            }`}
          >
            <SidebarHeader className="h-[52px] shrink-0 justify-center bg-[var(--chat-sidebar-mist)] px-3 py-2">
              <div className="flex w-full items-center gap-2">
                <div className="flex min-w-0 items-center gap-2 px-1 text-[var(--chat-ink)]">
                  <TeyaLogo size={18} priority />
                  <span className="truncate text-sm font-semibold">Teya</span>
                </div>
                <div className="ml-auto flex items-center gap-1">
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Button
                        variant="ghost"
                        className="size-8 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-4"
                        onClick={() => setIsSearchOpen(true)}
                        aria-label="Search chats"
                      >
                        <RoundedIcon icon={Search01Icon} />
                      </Button>
                    </TooltipTrigger>
                    <TooltipContent className="flex items-center gap-2">
                      <span>Search</span>
                      {user && (
                        <HotkeyBadge hotkey={{ key: 'k', meta: true }} />
                      )}
                    </TooltipContent>
                  </Tooltip>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Button
                        type="button"
                        variant="ghost"
                        className="size-8 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-4"
                        onClick={() => setOpen(false)}
                        aria-label="Close sidebar"
                      >
                        <RoundedIcon icon={PanelLeftCloseIcon} />
                      </Button>
                    </TooltipTrigger>
                    <TooltipContent>Close sidebar</TooltipContent>
                  </Tooltip>
                </div>
              </div>
            </SidebarHeader>
            <SidebarContent className="bg-[var(--chat-sidebar-mist)] px-1">
              <SidebarGroup className="pb-0">
                <SidebarGroupContent>
                  <SidebarMenu>
                    <SidebarMenuItem>
                      <SidebarMenuButton
                        type="button"
                        onClick={handleNewChatClick}
                        aria-label="New chat"
                        className="h-10 gap-3 bg-[var(--chat-hover)] px-2.5 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
                      >
                        <RoundedIcon icon={MessageAdd01Icon} />
                        <span className="font-medium">New chat</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                      <SidebarMenuButton
                        asChild
                        isActive={pathname.startsWith('/images')}
                        className="h-10 gap-3 px-2.5 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
                      >
                        <Link
                          href="/images"
                          onClick={() => setOpenMobile(false)}
                        >
                          <RoundedIcon icon={Image01Icon} />
                          <span className="font-medium">Images</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                      <SidebarMenuButton
                        asChild
                        isActive={pathname.startsWith('/library')}
                        className="h-10 gap-3 px-2.5 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
                      >
                        <Link
                          href="/library"
                          onClick={() => setOpenMobile(false)}
                        >
                          <RoundedIcon icon={LibraryIcon} />
                          <span className="font-medium">Library</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                      <SidebarMenuButton
                        asChild
                        isActive={pathname.startsWith('/plugins')}
                        className="h-10 gap-3 px-2.5 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
                      >
                        <Link
                          href="/plugins"
                          onClick={() => setOpenMobile(false)}
                        >
                          <RoundedIcon icon={Plug01Icon} />
                          <span className="font-medium">Plugins</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                      <SidebarMenuButton
                        asChild
                        isActive={pathname.startsWith('/projects')}
                        className="h-10 gap-3 px-2.5 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
                      >
                        <Link
                          href="/projects"
                          onClick={() => setOpenMobile(false)}
                        >
                          <RoundedIcon icon={Folder02Icon} />
                          <span className="font-medium">Projects</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <DisabledNavigationMenuItem item={pilotNavigationItem} />
                  </SidebarMenu>
                </SidebarGroupContent>
              </SidebarGroup>
              <SidebarHistory user={user} />
            </SidebarContent>
            <SidebarFooter className="shrink-0 border-t border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] p-3">
              {user ? (
                <SidebarUserNav user={user} />
              ) : (
                <Link
                  className="flex h-9 items-center justify-center rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-paper)] px-4 text-sm font-medium text-[var(--chat-ink)] hover:bg-[var(--chat-hover)]"
                  href="/login"
                >
                  Log in
                </Link>
              )}
            </SidebarFooter>
          </div>
        </div>
      </div>
      <ChatSearchDialog
        open={isSearchOpen}
        onOpenChange={setIsSearchOpen}
        user={user}
      />
    </Sidebar>
  );
}

function DisabledNavigationMenuItem({
  item,
}: {
  item: DisabledNavigationItem;
}) {
  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        type="button"
        disabled
        aria-label={`${item.label}, unavailable`}
        className="h-10 cursor-not-allowed gap-3 px-2.5 disabled:opacity-100 [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
      >
        <RoundedIcon icon={item.icon} />
        <span className="font-medium">{item.label}</span>
        {item.badge && (
          <span className="ml-auto rounded-full bg-[var(--chat-hover)] px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.08em] text-[var(--chat-mid-ash)]">
            {item.badge}
          </span>
        )}
      </SidebarMenuButton>
    </SidebarMenuItem>
  );
}

function RailButton({
  children,
  label,
  onClick,
}: {
  children: React.ReactNode;
  label: string;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
}) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          className="size-9 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-[19px] [&_svg]:stroke-[1.75]"
          onClick={onClick}
          aria-label={label}
        >
          {children}
        </Button>
      </TooltipTrigger>
      <TooltipContent side="right">{label}</TooltipContent>
    </Tooltip>
  );
}

function ChatSearchDialog({
  open,
  onOpenChange,
  user,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  user: User | undefined;
}) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const { data: chats, isLoading } = useSWR<Array<ChatSummary>>(
    user ? '/app/api/history' : null,
    fetcher,
  );

  const filtered = useMemo(() => {
    if (!chats) return [];
    if (!query.trim()) return chats;
    return chats.filter((chat) =>
      chat.title.toLowerCase().includes(query.trim().toLowerCase()),
    );
  }, [chats, query]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg rounded-[10px] border-border bg-popover text-popover-foreground shadow-none">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Search chats
          </DialogTitle>
        </DialogHeader>
        <Input
          autoFocus
          placeholder="Search by chat title..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="mb-3 h-10 rounded-[10px] border-input bg-background text-sm shadow-none focus-visible:ring-1 focus-visible:ring-ring"
        />
        <div className="max-h-72 overflow-y-auto">
          {isLoading ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Loading...
            </div>
          ) : filtered.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              No chats found
            </div>
          ) : (
            <ul className="space-y-1">
              {filtered.map((chat) => (
                <li key={chat.id}>
                  <button
                    type="button"
                    className="w-full rounded-[10px] px-3 py-2 text-left text-sm text-foreground transition-colors hover:bg-accent"
                    onClick={() => {
                      onOpenChange(false);
                      router.push(
                        chat.projectId
                          ? `/projects/${chat.projectId}/chat/${chat.id}`
                          : `/chat/${chat.id}`,
                      );
                    }}
                  >
                    {chat.title}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
