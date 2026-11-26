import { HugeiconsIcon, type HugeiconsIconProps } from '@hugeicons/react';

export function RoundedIcon({
  size = 20,
  strokeWidth = 1.7,
  ...props
}: HugeiconsIconProps) {
  return <HugeiconsIcon size={size} strokeWidth={strokeWidth} {...props} />;
}
