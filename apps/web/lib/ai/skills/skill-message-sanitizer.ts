import type { UIMessage } from 'ai';

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null;
}

function isLoadSkillPart(part: unknown): part is UnknownRecord {
  if (!isRecord(part) || part.type !== 'tool-invocation') {
    return false;
  }
  const invocation = part.toolInvocation;
  return isRecord(invocation) && invocation.toolName === 'loadSkill';
}

export function stripLoadedSkillsFromMessages(
  messages: UIMessage[],
): UIMessage[] {
  return messages.flatMap((message) => {
    const parts = message.parts.filter((part) => !isLoadSkillPart(part));
    if (message.role === 'assistant' && parts.length === 0) {
      return [];
    }
    return [{ ...message, parts }];
  });
}

export function redactLoadedSkillInstructions(parts: unknown[]): unknown[] {
  return parts.map((part) => {
    if (!isLoadSkillPart(part)) {
      return part;
    }
    const invocation = part.toolInvocation as UnknownRecord;
    if (invocation.state !== 'result' || !isRecord(invocation.result)) {
      return part;
    }
    const id =
      typeof invocation.result.id === 'string' ? invocation.result.id : '';
    const name =
      typeof invocation.result.name === 'string'
        ? invocation.result.name
        : 'Skill';
    return {
      ...part,
      toolInvocation: {
        ...invocation,
        result: { id, name },
      },
    };
  });
}
