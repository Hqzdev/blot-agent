import type { ComponentProps } from 'react';

import { RoundedIcon } from '@/components/ui/rounded-icon';
import { type SidebarTrigger, useSidebar } from '@/components/ui/sidebar';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { PanelLeftIcon } from '@hugeicons/core-free-icons';

import { cn } from '@/lib/utils';
import { Button } from './ui/button';

export function SidebarToggle({
  className,
}: ComponentProps<typeof SidebarTrigger>) {
  const { toggleSidebar } = useSidebar();

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          onClick={toggleSidebar}
          variant="ghost"
          className={cn(
            'size-8 rounded-[10px] p-0 text-[#0d0d0d] shadow-none hover:bg-[#0000000d] hover:text-[#0d0d0d] [&_svg]:size-4',
            className,
          )}
          aria-label="Toggle sidebar"
        >
          <RoundedIcon icon={PanelLeftIcon} />
        </Button>
      </TooltipTrigger>
      <TooltipContent align="start">Toggle Sidebar</TooltipContent>
    </Tooltip>
  );
}
