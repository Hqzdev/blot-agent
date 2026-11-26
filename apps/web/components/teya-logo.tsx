import { cn } from '@/lib/utils';
import Image from 'next/image';

interface TeyaLogoProps {
  className?: string;
  priority?: boolean;
  size?: number;
}

export function TeyaLogo({
  className,
  priority = false,
  size = 20,
}: TeyaLogoProps) {
  return (
    <Image
      src="/app/teya-logo.png"
      alt="Teya"
      width={size}
      height={size}
      className={cn(
        'shrink-0 select-none object-contain dark:invert',
        className,
      )}
      draggable={false}
      priority={priority}
    />
  );
}
