'use client';
import { ArrowRight01Icon } from '@hugeicons/core-free-icons';
import type { User } from 'next-auth';

import { ProfileMenu } from '@/components/profile-menu';
import { RoundedIcon } from '@/components/ui/rounded-icon';
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar';

export function SidebarUserNav({ user }: { user: User }) {
  const displayName = (
    user.nickname ||
    user.name ||
    user.email ||
    'Teya user'
  ).trim();
  const initials = displayName.slice(0, 2).toUpperCase();
  const plan = user.subscription || 'free';
  const planLabel = plan.charAt(0).toUpperCase() + plan.slice(1);

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <ProfileMenu user={user} align="start" side="top">
          <SidebarMenuButton className="h-auto min-h-14 gap-3 rounded-[12px] px-2 py-2 text-[var(--chat-ink)] hover:bg-[var(--chat-hover)] hover:text-[var(--chat-ink)]">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-[#4a9df8] text-xs font-semibold text-white">
              {initials}
            </span>
            <span className="flex min-w-0 flex-1 flex-col items-start">
              <span className="w-full truncate text-left text-sm font-medium">
                {displayName}
              </span>
              <span className="text-xs text-[var(--chat-mid-ash)]">
                {planLabel}
              </span>
            </span>
            <RoundedIcon
              icon={ArrowRight01Icon}
              className="shrink-0 text-[var(--chat-mid-ash)]"
              size={17}
            />
          </SidebarMenuButton>
        </ProfileMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  );
}
