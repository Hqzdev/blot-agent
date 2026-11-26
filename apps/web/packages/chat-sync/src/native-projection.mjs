import { logicalID } from './replica.mjs';

export function conversationAliases(records) {
  const chats = [...records.values()]
    .filter((record) => record.kind === 'Conversation' && !record.deleted)
    .map((record) => JSON.parse(record.payload));
  chats.sort(
    (a, b) =>
      Date.parse(a.metadata.createdAt) - Date.parse(b.metadata.createdAt) ||
      a.metadata.id.toUpperCase().localeCompare(b.metadata.id.toUpperCase()),
  );
  const families = new Map();
  const aliases = new Map();
  for (const chat of chats) {
    const id = chat.metadata.id.toLowerCase();
    const family =
      chat.kind === 'GROUP' ? id : (chat.agentId || 'unassigned').toLowerCase();
    if (!families.has(family)) families.set(family, id);
    aliases.set(id, families.get(family));
  }
  return aliases;
}

export function messageText(parts) {
  return Array.isArray(parts)
    ? parts
        .filter(
          (part) => part?.type === 'text' && typeof part.text === 'string',
        )
        .map((part) => part.text)
        .join('\n')
    : '';
}

export function messagePositions(records, aliases) {
  const messages = [...records.values()]
    .filter((record) => record.kind === 'Message' && !record.deleted)
    .map((record) => JSON.parse(record.payload));
  messages.sort(
    (a, b) =>
      Date.parse(a.metadata.createdAt) - Date.parse(b.metadata.createdAt) ||
      a.metadata.id.localeCompare(b.metadata.id),
  );
  const groups = new Map();
  for (const message of messages) {
    const original = message.conversationId.toLowerCase();
    const canonical = aliases.get(original);
    if (!canonical) continue;
    if (!groups.has(canonical)) groups.set(canonical, new Map());
    const streams = groups.get(canonical);
    if (!streams.has(original)) streams.set(original, []);
    streams.get(original).push(message);
  }
  const positions = new Map();
  for (const grouped of groups.values()) {
    const streams = [...grouped.values()].map((stream) =>
      stream
        .map((message, index) => ({
          message,
          position: message.position ?? index + 1,
        }))
        .sort(
          (a, b) =>
            a.position - b.position ||
            a.message.metadata.id.localeCompare(b.message.metadata.id),
        )
        .map((item) => item.message),
    );
    const offsets = streams.map(() => 0);
    let position = 0;
    while (streams.some((stream, index) => offsets[index] < stream.length)) {
      const candidates = streams
        .map((stream, index) => ({ message: stream[offsets[index]], index }))
        .filter((item) => item.message);
      candidates.sort(
        (a, b) =>
          Date.parse(a.message.metadata.createdAt) -
            Date.parse(b.message.metadata.createdAt) ||
          a.message.metadata.id.localeCompare(b.message.metadata.id),
      );
      const next = candidates[0];
      offsets[next.index]++;
      positions.set(next.message.metadata.id.toLowerCase(), ++position);
    }
  }
  return positions;
}

export class NativeChatProjection {
  constructor(editor) {
    this.editor = editor;
  }

  applyEvent(event) {
    const id = event.record_id.toLowerCase();
    if (event.deleted) {
      if (event.kind === 'Conversation') {
        const aliases = conversationAliases(this.editor.records);
        const family = new Set([
          id,
          ...[...aliases]
            .filter(([, canonical]) => canonical === id)
            .map(([alias]) => alias),
        ]);
        for (const record of this.editor.records.values()) {
          if (
            record.kind === 'Message' &&
            !record.deleted &&
            family.has(JSON.parse(record.payload).conversationId.toLowerCase())
          )
            this.editor.remove('Message', record.recordID);
        }
        for (const member of family) {
          this.editor.remove('Conversation', member);
          const agent = logicalID(this.editor.account.id, `agent:${member}`);
          if (this.editor.records.has(`AgentProfile:${agent}`))
            this.editor.remove('AgentProfile', agent);
        }
      } else this.editor.remove(event.kind, id);
      return;
    }
    const row = event.payload;
    const date = new Date(row.created_at)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');
    const old = this.editor.records.get(`${event.kind}:${id}`);
    if (old?.deleted) return;
    if (event.kind === 'Conversation') {
      if (old) this.editor.put('Conversation', id, { title: row.title }, date);
      else {
        const agent = logicalID(this.editor.account.id, `agent:${id}`);
        this.editor.put(
          'AgentProfile',
          agent,
          {
            name: row.title,
            roleId: 'custom',
            avatarShape: 'circle',
            avatarColor: 'blue',
            instructions: '',
            modelId: 'gigachat',
            accessMode: 'ASK_FIRST',
            configurationId: null,
          },
          date,
        );
        this.editor.put(
          'Conversation',
          id,
          {
            agentId: agent,
            title: row.title,
            mobileOwned: false,
            pinned: false,
            archived: false,
            kind: 'DIRECT',
          },
          date,
        );
      }
    } else if (event.kind === 'Message') {
      const previous = old && JSON.parse(old.payload);
      const content = messageText(row.parts);
      // Preserve native attribution/tool metadata when an unchanged web row is replayed.
      if (previous && previous.content === content) return;
      const parent = this.editor.records.get(
        `Conversation:${row.chat_id.toLowerCase()}`,
      );
      if (!parent || parent.deleted) return;
      const chat = JSON.parse(parent.payload);
      const role =
        row.role === 'user'
          ? 'USER'
          : row.role === 'system'
            ? 'SYSTEM'
            : 'ASSISTANT';
      if (previous?.role === 'USER' && previous.content !== content)
        throw new Error('User messages are immutable');
      const positions = [...this.editor.records.values()]
        .filter((record) => record.kind === 'Message' && !record.deleted)
        .map((record) => JSON.parse(record.payload))
        .filter(
          (message) =>
            message.conversationId.toLowerCase() === row.chat_id.toLowerCase(),
        )
        .map((message) => message.position || 0);
      this.editor.put(
        'Message',
        id,
        {
          conversationId: row.chat_id.toLowerCase(),
          role,
          content,
          delivery: 'COMPLETED',
          commandId: previous?.commandId || id,
          artifactIds: previous?.artifactIds || [],
          authorAgentId: null,
          replyToMessageId: previous?.replyToMessageId ?? null,
          mentions: previous?.mentions ?? null,
          executorDeviceId: null,
          position: previous?.position ?? Math.max(0, ...positions) + 1,
          ...(role === 'ASSISTANT'
            ? {
                authorAgentId: chat.agentId || null,
                executorDeviceId: this.editor.device,
              }
            : {}),
        },
        date,
      );
    }
  }
}
