'use client';

import { ProfileMenu } from '@/components/profile-menu';
import { SidebarToggle } from '@/components/sidebar-toggle';
import { Button } from '@/components/ui/button';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import { useSidebar } from '@/components/ui/sidebar';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { useHotkeys } from '@/hooks/use-hotkeys';
import { useOS } from '@/hooks/use-os';
import {
  MessageAdd01Icon,
  SparklesIcon,
  UserCircle02Icon,
} from '@hugeicons/core-free-icons';
import { useSession } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { memo, useState } from 'react';
import { KeyboardShortcutsDialog } from './keyboard-shortcuts-dialog';
import { ModelSelector } from './model-selector';
import { UpgradePlanDialog } from './upgrade-plan-dialog';

function PureChatHeader({
  selectedModelId,
  onModelChange,
}: {
  selectedModelId: string;
  onModelChange: (modelId: string) => void;
}) {
  const router = useRouter();
  const { isMobile } = useSidebar();
  const [isUpgradeOpen, setIsUpgradeOpen] = useState(false);
  const [isShortcutsOpen, setIsShortcutsOpen] = useState(false);
  const os = useOS();
  const { data: session } = useSession();

  useHotkeys(
    { key: '/', meta: true },
    (event) => {
      event.preventDefault();
      setIsShortcutsOpen(true);
    },
    { os },
  );

  const isFreePlan = session?.user?.subscription === 'free';

  return (
    <header className="absolute inset-x-0 top-0 z-50 flex h-[52px] items-center justify-between bg-[var(--chat-paper)] px-3 md:px-5">
      <div className="flex min-w-0 items-center gap-1">
        {isMobile && (
          <>
            <SidebarToggle />
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  className="size-8 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-4"
                  onClick={() => {
                    router.push('/chat');
                    router.refresh();
                  }}
                  aria-label="New chat"
                >
                  <RoundedIcon icon={MessageAdd01Icon} />
                </Button>
              </TooltipTrigger>
              <TooltipContent>New chat</TooltipContent>
            </Tooltip>
          </>
        )}
        <ModelSelector
          selectedModelId={selectedModelId}
          onModelChange={onModelChange}
          className="ml-1"
        />
      </div>

      <div className="ml-auto flex shrink-0 items-center gap-1">
        {isFreePlan && (
          <Button
            variant="ghost"
            size="sm"
            className="h-8 rounded-full bg-transparent px-2.5 text-sm font-medium text-[#4d9bf5] shadow-none hover:bg-[#4d9bf51a] hover:text-[#4d9bf5]"
            onClick={() => setIsUpgradeOpen(true)}
          >
            <RoundedIcon
              icon={SparklesIcon}
              className="mr-1"
              size={16}
              strokeWidth={1.8}
            />
            Upgrade
          </Button>
        )}
        {session?.user ? (
          <ProfileMenu user={session.user} align="end" side="bottom">
            <Button
              variant="ghost"
              className="size-8 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-[18px]"
              aria-label="Account menu"
            >
              <RoundedIcon icon={UserCircle02Icon} size={19} />
            </Button>
          </ProfileMenu>
        ) : (
          <Button
            variant="ghost"
            className="size-8 rounded-[10px] p-0 text-[var(--chat-ink)] shadow-none hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)] [&_svg]:size-[18px]"
            onClick={() => router.push('/login')}
            aria-label="Log in"
          >
            <RoundedIcon icon={UserCircle02Icon} size={19} />
          </Button>
        )}
      </div>

      {session?.user && (
        <UpgradePlanDialog
          open={isUpgradeOpen}
          onOpenChange={setIsUpgradeOpen}
        />
      )}
      <KeyboardShortcutsDialog
        open={isShortcutsOpen}
        onOpenChange={setIsShortcutsOpen}
      />
    </header>
  );
}

export const ChatHeader = memo(PureChatHeader);
