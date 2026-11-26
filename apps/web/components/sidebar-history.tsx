'use client';

import {
  Alert02Icon,
  Delete02Icon,
  MoreHorizontalIcon,
  PencilEdit01Icon,
} from '@hugeicons/core-free-icons';
import { isToday } from 'date-fns/isToday';
import { isYesterday } from 'date-fns/isYesterday';
import { subMonths } from 'date-fns/subMonths';
import { subWeeks } from 'date-fns/subWeeks';
import type { User } from 'next-auth';
import Link from 'next/link';
import { useParams, usePathname, useRouter } from 'next/navigation';
import { memo, useEffect, useState } from 'react';
import { toast } from 'sonner';
import useSWR from 'swr';

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
import { RoundedIcon } from '@/components/ui/rounded-icon';
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar';
import type { ChatSummary } from '@/lib/db/schema';
import { fetcher } from '@/lib/utils';

type GroupedChats = {
  today: ChatSummary[];
  yesterday: ChatSummary[];
  lastWeek: ChatSummary[];
  lastMonth: ChatSummary[];
  older: ChatSummary[];
};

type PureChatItemProps = {
  chat: ChatSummary;
  isActive: boolean;
  onDelete: (chatId: string) => void;
  setOpenMobile: (open: boolean) => void;
  onRename: (chat: ChatSummary) => void;
};

const PureChatItem = ({
  chat,
  isActive,
  onDelete,
  setOpenMobile,
  onRename,
  hoveredId,
  setHoveredId,
}: PureChatItemProps & {
  hoveredId?: string | null;
  setHoveredId?: (id: string | null) => void;
}) => {
  return (
    <SidebarMenuItem
      onMouseEnter={() => setHoveredId && setHoveredId(chat.id)}
      onMouseLeave={() => setHoveredId && setHoveredId(null)}
    >
      <SidebarMenuButton asChild isActive={isActive}>
        <Link
          href={
            chat.projectId
              ? `/projects/${chat.projectId}/chat/${chat.id}`
              : `/chat/${chat.id}`
          }
          onClick={() => setOpenMobile(false)}
          className={chat.projectName ? 'h-10 py-1' : undefined}
        >
          <span className="min-w-0 flex-1">
            <span className="block truncate">{chat.title}</span>
            {chat.projectName && (
              <span className="mt-0.5 flex items-center gap-1.5 truncate text-[11px] text-[var(--chat-hollow)]">
                {chat.projectName}
                <span className="size-1.5 shrink-0 rounded-full bg-[#4d9bf5]" />
              </span>
            )}
          </span>
        </Link>
      </SidebarMenuButton>

      <DropdownMenu modal={true}>
        <DropdownMenuTrigger asChild>
          <SidebarMenuAction
            className={`mr-0.5 bg-transparent text-[var(--chat-mid-ash)] transition-opacity duration-150 hover:bg-[var(--chat-hover)] focus:bg-[var(--chat-hover)] ${hoveredId === chat.id || isActive ? 'opacity-100' : 'opacity-0'}`}
            showOnHover={!isActive}
          >
            <RoundedIcon icon={MoreHorizontalIcon} size={16} />
            <span className="sr-only">More</span>
          </SidebarMenuAction>
        </DropdownMenuTrigger>

        <DropdownMenuContent
          side="bottom"
          align="start"
          className="min-w-[180px] rounded-[10px] border-border bg-popover p-1 text-popover-foreground shadow-none"
        >
          <DropdownMenuItem
            className="cursor-pointer rounded-lg focus:bg-accent"
            onSelect={() => {
              onRename(chat);
            }}
          >
            <RoundedIcon icon={PencilEdit01Icon} size={16} />
            <span>Rename</span>
          </DropdownMenuItem>

          <DropdownMenuItem
            className="cursor-pointer rounded-lg text-popover-foreground focus:bg-accent focus:text-accent-foreground"
            onSelect={() => {
              onDelete(chat.id);
            }}
          >
            <RoundedIcon icon={Delete02Icon} size={16} />
            <span>Delete</span>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </SidebarMenuItem>
  );
};

export const ChatItem = memo(PureChatItem, (prevProps, nextProps) => {
  if (prevProps.isActive !== nextProps.isActive) return false;
  return true;
});

export function SidebarHistory({ user }: { user: User | undefined }) {
  const { setOpenMobile } = useSidebar();
  const { id } = useParams();
  const pathname = usePathname();
  const {
    data: history,
    isLoading,
    error,
    mutate,
  } = useSWR<Array<ChatSummary>>(user ? '/app/api/history' : null, fetcher, {
    revalidateOnFocus: true,
    refreshInterval: 5000,
    revalidateOnReconnect: true,
    shouldRetryOnError: true,
    errorRetryCount: 3,
    onError: (err) => {
      console.error('Failed to load chat history:', err);
    },
  });

  useEffect(() => {
    if (user && pathname) {
      const timeoutId = setTimeout(() => {
        mutate();
      }, 100);
      return () => clearTimeout(timeoutId);
    }
  }, [pathname, user, mutate]);

  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [hoveredId, setHoveredId] = useState<string | null>(null);

  const [renameChat, setRenameChat] = useState<ChatSummary | null>(null);
  const [renameValue, setRenameValue] = useState('');
  const [isRenaming, setIsRenaming] = useState(false);

  const router = useRouter();

  const handleDelete = async () => {
    const deletePromise = fetch(`/app/api/chat?id=${deleteId}`, {
      method: 'DELETE',
    });

    toast.promise(deletePromise, {
      loading: 'Deleting chat...',
      success: () => {
        mutate((history) => {
          if (history) {
            return history.filter((chat) => chat.id !== deleteId);
          }
        });
        return 'Chat deleted successfully';
      },
      error: 'Failed to delete chat',
    });

    setIsDeleteDialogOpen(false);

    if (deleteId === id) {
      const deletedChat = history?.find((chat) => chat.id === deleteId);
      router.push(
        deletedChat?.projectId ? `/projects/${deletedChat.projectId}` : '/chat',
      );
    }
  };

  const handleRename = async () => {
    if (!renameChat) return;
    setIsRenaming(true);

    const renamePromise = fetch(`/app/api/chat?id=${renameChat.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: renameValue }),
    });

    toast.promise(renamePromise, {
      loading: 'Renaming chat...',
      success: async () => {
        await mutate();
        setRenameChat(null);
        setRenameValue('');
        setIsRenaming(false);
        return 'Chat renamed successfully';
      },
      error: () => {
        setIsRenaming(false);
        return 'Failed to rename chat';
      },
    });
  };

  if (!user) {
    return (
      <SidebarGroup>
        <SidebarGroupContent>
          <div className="flex w-full items-center justify-center px-2 py-6 text-center text-sm leading-5 text-[var(--chat-hollow)]">
            Login to save and revisit previous chats!
          </div>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  }

  if (error) {
    console.error('Error loading chat history:', error);
    return (
      <SidebarGroup>
        <SidebarGroupContent>
          <div className="flex w-full items-center justify-center px-2 py-6 text-center text-sm leading-5 text-[var(--chat-mid-ash)]">
            Failed to load chats. Please refresh the page.
          </div>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  }

  if (isLoading) {
    return (
      <SidebarGroup>
        <div className="px-2 py-1 text-xs font-medium text-[var(--chat-hollow)]">
          Today
        </div>
        <SidebarGroupContent>
          <div className="flex flex-col">
            {[44, 32, 28, 64, 52].map((item) => (
              <div
                key={item}
                className="flex h-8 items-center gap-2 rounded-[10px] px-2"
              >
                <div
                  className="h-3.5 max-w-[--skeleton-width] flex-1 rounded bg-[var(--chat-hover)]"
                  style={
                    {
                      '--skeleton-width': `${item}%`,
                    } as React.CSSProperties
                  }
                />
              </div>
            ))}
          </div>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  }

  if (history?.length === 0) {
    return (
      <SidebarGroup>
        <SidebarGroupContent>
          <div className="flex w-full items-center justify-center px-2 py-6 text-center text-sm leading-5 text-[#8f8f8f]">
            Start a chat to see your conversation history here!
          </div>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  }

  const groupChatsByDate = (chats: ChatSummary[]): GroupedChats => {
    const now = new Date();
    const oneWeekAgo = subWeeks(now, 1);
    const oneMonthAgo = subMonths(now, 1);

    return chats.reduce(
      (groups, chat) => {
        const chatDate = new Date(chat.createdAt);

        if (isToday(chatDate)) {
          groups.today.push(chat);
        } else if (isYesterday(chatDate)) {
          groups.yesterday.push(chat);
        } else if (chatDate > oneWeekAgo) {
          groups.lastWeek.push(chat);
        } else if (chatDate > oneMonthAgo) {
          groups.lastMonth.push(chat);
        } else {
          groups.older.push(chat);
        }

        return groups;
      },
      {
        today: [],
        yesterday: [],
        lastWeek: [],
        lastMonth: [],
        older: [],
      } as GroupedChats,
    );
  };

  return (
    <>
      <SidebarGroup>
        <SidebarGroupContent>
          <SidebarMenu>
            {history &&
              (() => {
                const groupedChats = groupChatsByDate(history);

                return (
                  <>
                    {groupedChats.today.length > 0 && (
                      <>
                        <div className="px-2 py-1 text-xs font-medium text-[#8f8f8f]">
                          Today
                        </div>
                        {groupedChats.today.map((chat) => (
                          <ChatItem
                            key={chat.id}
                            chat={chat}
                            isActive={chat.id === id}
                            onDelete={(chatId) => {
                              setDeleteId(chatId);
                              setIsDeleteDialogOpen(true);
                            }}
                            setOpenMobile={setOpenMobile}
                            onRename={(chat) => {
                              setRenameChat(chat);
                              setRenameValue(chat.title);
                            }}
                            hoveredId={hoveredId}
                            setHoveredId={setHoveredId}
                          />
                        ))}
                      </>
                    )}

                    {groupedChats.yesterday.length > 0 && (
                      <>
                        <div className="mt-4 px-2 py-1 text-xs font-medium text-[#8f8f8f]">
                          Yesterday
                        </div>
                        {groupedChats.yesterday.map((chat) => (
                          <ChatItem
                            key={chat.id}
                            chat={chat}
                            isActive={chat.id === id}
                            onDelete={(chatId) => {
                              setDeleteId(chatId);
                              setIsDeleteDialogOpen(true);
                            }}
                            setOpenMobile={setOpenMobile}
                            onRename={(chat) => {
                              setRenameChat(chat);
                              setRenameValue(chat.title);
                            }}
                            hoveredId={hoveredId}
                            setHoveredId={setHoveredId}
                          />
                        ))}
                      </>
                    )}

                    {groupedChats.lastWeek.length > 0 && (
                      <>
                        <div className="mt-4 px-2 py-1 text-xs font-medium text-[#8f8f8f]">
                          Last 7 days
                        </div>
                        {groupedChats.lastWeek.map((chat) => (
                          <ChatItem
                            key={chat.id}
                            chat={chat}
                            isActive={chat.id === id}
                            onDelete={(chatId) => {
                              setDeleteId(chatId);
                              setIsDeleteDialogOpen(true);
                            }}
                            setOpenMobile={setOpenMobile}
                            onRename={(chat) => {
                              setRenameChat(chat);
                              setRenameValue(chat.title);
                            }}
                            hoveredId={hoveredId}
                            setHoveredId={setHoveredId}
                          />
                        ))}
                      </>
                    )}

                    {groupedChats.lastMonth.length > 0 && (
                      <>
                        <div className="mt-4 px-2 py-1 text-xs font-medium text-[#8f8f8f]">
                          Last 30 days
                        </div>
                        {groupedChats.lastMonth.map((chat) => (
                          <ChatItem
                            key={chat.id}
                            chat={chat}
                            isActive={chat.id === id}
                            onDelete={(chatId) => {
                              setDeleteId(chatId);
                              setIsDeleteDialogOpen(true);
                            }}
                            setOpenMobile={setOpenMobile}
                            onRename={(chat) => {
                              setRenameChat(chat);
                              setRenameValue(chat.title);
                            }}
                            hoveredId={hoveredId}
                            setHoveredId={setHoveredId}
                          />
                        ))}
                      </>
                    )}

                    {groupedChats.older.length > 0 && (
                      <>
                        <div className="mt-4 px-2 py-1 text-xs font-medium text-[#8f8f8f]">
                          Older
                        </div>
                        {groupedChats.older.map((chat) => (
                          <ChatItem
                            key={chat.id}
                            chat={chat}
                            isActive={chat.id === id}
                            onDelete={(chatId) => {
                              setDeleteId(chatId);
                              setIsDeleteDialogOpen(true);
                            }}
                            setOpenMobile={setOpenMobile}
                            onRename={(chat) => {
                              setRenameChat(chat);
                              setRenameValue(chat.title);
                            }}
                            hoveredId={hoveredId}
                            setHoveredId={setHoveredId}
                          />
                        ))}
                      </>
                    )}
                  </>
                );
              })()}
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
      <Dialog open={isDeleteDialogOpen} onOpenChange={setIsDeleteDialogOpen}>
        <DialogContent className="rounded-[10px] border-border bg-background text-foreground shadow-none">
          <DialogHeader>
            <DialogTitle className="mb-1 text-base font-semibold">
              Delete chat
            </DialogTitle>
          </DialogHeader>

          <div className="text-sm leading-5 text-muted-foreground">
            Are you sure you want to delete this chat? This action cannot be
            undone.
          </div>

          <div className="flex items-start gap-2 rounded-[10px] border border-border bg-muted p-3 text-sm text-muted-foreground">
            <RoundedIcon
              icon={Alert02Icon}
              className="shrink-0 text-foreground"
              size={16}
            />
            <div>
              <strong>
                Warning:{' '}
                <span className="text-foreground">
                  This action is permanent
                </span>
              </strong>
              <div className="mt-0.5 text-xs leading-4 text-muted-foreground">
                All messages and history in this chat will be permanently
                deleted.
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button
              variant="ghost"
              className="rounded-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
              onClick={() => setIsDeleteDialogOpen(false)}
            >
              Cancel
            </Button>
            <Button
              className="rounded-[10px] bg-primary text-primary-foreground hover:bg-primary/90"
              onClick={handleDelete}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <Dialog
        open={!!renameChat}
        onOpenChange={(open) => {
          if (!open) {
            setRenameChat(null);
            setRenameValue('');
          }
        }}
      >
        <DialogContent className="rounded-[10px] border-border bg-background text-foreground shadow-none">
          <DialogHeader>
            <DialogTitle className="mb-1 text-base font-semibold">
              Rename chat
            </DialogTitle>
          </DialogHeader>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleRename();
            }}
          >
            <div className="mb-4">
              <input
                className="w-full rounded-[10px] border border-input bg-background px-3 py-2 text-sm text-foreground outline-none focus:border-ring"
                type="text"
                value={renameValue}
                onChange={(e) => setRenameValue(e.target.value)}
                maxLength={100}
                placeholder="Enter new chat name"
                disabled={isRenaming}
              />
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="ghost"
                className="rounded-[10px] text-muted-foreground hover:bg-accent hover:text-foreground"
                onClick={() => {
                  setRenameChat(null);
                  setRenameValue('');
                }}
                disabled={isRenaming}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                className="rounded-[10px] bg-primary text-primary-foreground hover:bg-primary/90"
                disabled={
                  isRenaming ||
                  !renameValue.trim() ||
                  renameValue === renameChat?.title
                }
              >
                {isRenaming ? 'Renaming...' : 'Rename'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
