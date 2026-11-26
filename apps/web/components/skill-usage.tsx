'use client';

import { RoundedIcon } from '@/components/ui/rounded-icon';
import { AiBrain01Icon } from '@hugeicons/core-free-icons';

export function SkillUsage({
  result,
}: {
  result?: unknown;
}) {
  const name =
    typeof result === 'object' &&
    result !== null &&
    'name' in result &&
    typeof result.name === 'string'
      ? result.name
      : null;
  return (
    <div
      data-testid="skill-usage"
      className="flex w-fit items-center gap-1.5 rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-hover)] px-2.5 py-1 text-xs text-[var(--chat-mid-ash)]"
    >
      <RoundedIcon icon={AiBrain01Icon} size={14} />
      <span>{name ? `Used skill: ${name}` : 'Loading skill…'}</span>
    </div>
  );
}
