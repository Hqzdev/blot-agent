import type { DBMessage } from '@/lib/db/schema';
import type { Attachment, UIMessage } from 'ai';

export function toUIMessages(messages: DBMessage[]): UIMessage[] {
  return messages.map((message) => {
    const parts =
      Array.isArray(message.parts) && message.parts.length > 0
        ? (message.parts as UIMessage['parts'])
        : [{ type: 'text' as const, text: '' }];
    return {
      id: message.id,
      parts,
      role: message.role as UIMessage['role'],
      content: '',
      createdAt: message.createdAt,
      experimental_attachments:
        (message.attachments as Array<Attachment>) ?? [],
    };
  });
}
