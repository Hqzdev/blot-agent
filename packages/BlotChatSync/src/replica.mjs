import { createHash } from 'node:crypto';

export function stableJSON(value) {
  return JSON.stringify(value, (_key, item) =>
    item && typeof item === 'object' && !Array.isArray(item)
      ? Object.fromEntries(
          Object.entries(item).sort(([a], [b]) => a.localeCompare(b)),
        )
      : item,
  );
}

export const uuid = (value) =>
  typeof value === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export const supportedKinds = new Set([
  'Conversation',
  'Message',
  'AgentProfile',
  'AgentConfigurationRevision',
  'ConversationParticipant',
]);
export const dominates = (left, right) =>
  Object.entries(right).every(([id, sequence]) => (left[id] || 0) >= sequence);
export function mergeClock(left, right) {
  const clock = { ...left };
  for (const [id, sequence] of Object.entries(right))
    clock[id] = Math.max(clock[id] || 0, sequence);
  return clock;
}
export function logicalID(owner, purpose) {
  const hash = createHash('sha256')
    .update(`BLOT-CHAT-SYNC-1:${owner}:${purpose}`)
    .digest('hex');
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-5${hash.slice(13, 16)}-a${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}
export function validClock(clock) {
  return (
    clock &&
    typeof clock === 'object' &&
    !Array.isArray(clock) &&
    Object.keys(clock).length <= 4096 &&
    Object.entries(clock).every(
      ([id, sequence]) =>
        uuid(id) &&
        id === id.toLowerCase() &&
        Number.isSafeInteger(sequence) &&
        sequence >= 0,
    )
  );
}
function wins(candidate, current) {
  if (dominates(candidate.vector, current.vector)) return true;
  if (dominates(current.vector, candidate.vector)) return false;
  return candidate.origin.toUpperCase() === current.origin.toUpperCase()
    ? candidate.sequence > current.sequence
    : candidate.origin.toUpperCase() > current.origin.toUpperCase();
}
export function validateRecord(record, account) {
  if (!supportedKinds.has(record.kind)) return null;
  if (
    !uuid(record.recordID) ||
    !uuid(record.origin) ||
    !Number.isSafeInteger(record.version) ||
    record.version < 1 ||
    !Number.isSafeInteger(record.sequence) ||
    record.sequence < 1 ||
    !validClock(record.vector) ||
    (record.vector[record.origin.toLowerCase()] || 0) < record.sequence ||
    record.deleted !== (record.payload == null) ||
    !record.fields ||
    typeof record.fields !== 'object' ||
    Array.isArray(record.fields)
  )
    throw new Error('Invalid chat replica record');
  const result = {
    ...record,
    payload: record.payload ?? null,
    recordID: record.recordID.toLowerCase(),
    origin: record.origin.toLowerCase(),
  };
  let payload;
  if (!record.deleted) {
    if (
      typeof record.payload !== 'string' ||
      Buffer.byteLength(record.payload) > 192 * 1024
    )
      throw new Error('Invalid chat payload');
    payload = JSON.parse(record.payload);
    const metadata = payload.metadata;
    if (
      !metadata ||
      metadata.id?.toLowerCase() !== result.recordID ||
      metadata.ownerId?.toLowerCase() !== account.id ||
      metadata.workspaceId?.toLowerCase() !== account.workspace_id ||
      metadata.version !== record.version ||
      !Number.isFinite(Date.parse(metadata.createdAt)) ||
      !Number.isFinite(Date.parse(metadata.updatedAt))
    )
      throw new Error('Chat replica identity mismatch');
    if (
      record.kind === 'Conversation' &&
      ((!uuid(payload.agentId) &&
        payload.agentId !== null &&
        payload.agentId !== undefined) ||
        typeof payload.title !== 'string' ||
        ![undefined, null, 'DIRECT', 'GROUP'].includes(payload.kind))
    )
      throw new Error('Invalid conversation');
    if (
      record.kind === 'Message' &&
      (!uuid(payload.conversationId) ||
        !['USER', 'ASSISTANT', 'TOOL', 'SYSTEM'].includes(payload.role) ||
        typeof payload.content !== 'string' ||
        !uuid(payload.commandId) ||
        !Array.isArray(payload.artifactIds) ||
        payload.artifactIds.some((id) => !uuid(id)))
    )
      throw new Error('Invalid message');
    if (
      record.kind === 'Message' &&
      payload.role === 'ASSISTANT' &&
      payload.executorDeviceId &&
      payload.executorDeviceId.toLowerCase() !== result.origin
    )
      throw new Error('Invalid assistant executor');
  }
  for (const [key, stamp] of Object.entries(record.fields)) {
    if (
      key === 'metadata' ||
      (payload && !Object.hasOwn(payload, key)) ||
      !uuid(stamp.origin) ||
      !Number.isSafeInteger(stamp.sequence) ||
      stamp.sequence < 1 ||
      !validClock(stamp.vector) ||
      stamp.vector[stamp.origin.toLowerCase()] !== stamp.sequence ||
      !dominates(record.vector, stamp.vector)
    )
      throw new Error('Invalid chat field stamp');
  }
  return result;
}

export function mergeRecord(current, incoming) {
  if (!current) return incoming;
  const vector = mergeClock(current.vector, incoming.vector);
  if (current.deleted || incoming.deleted)
    return {
      ...(incoming.deleted && !current.deleted ? incoming : current),
      vector,
    };
  const old = JSON.parse(current.payload);
  const next = JSON.parse(incoming.payload);
  if (
    incoming.kind === 'Message' &&
    old.role === 'USER' &&
    old.content !== next.content
  )
    throw new Error('User messages are immutable');
  if (dominates(current.vector, incoming.vector)) return current;
  if (incoming.kind === 'AgentConfigurationRevision') {
    const { metadata: leftMetadata, ...left } = old;
    const { metadata: rightMetadata, ...right } = next;
    if (stableJSON(left) !== stableJSON(right))
      throw new Error('Agent revisions are immutable');
  }
  const winner = wins(incoming, current) ? incoming : current;
  if (
    incoming.kind === 'AgentProfile' &&
    !dominates(incoming.vector, current.vector)
  )
    return { ...winner, vector };
  if (
    incoming.kind === 'ConversationParticipant' &&
    !dominates(incoming.vector, current.vector) &&
    old.removed !== next.removed
  )
    return { ...(old.removed ? current : incoming), vector };
  const fields = { ...current.fields };
  const payload = { ...old };
  for (const [key, candidate] of Object.entries(incoming.fields))
    if (!fields[key] || wins(candidate, fields[key])) {
      payload[key] = next[key];
      fields[key] = candidate;
    }
  payload.metadata = JSON.parse(winner.payload).metadata;
  return { ...winner, vector, fields, payload: JSON.stringify(payload) };
}

export class WebReplicaEditor {
  constructor(account, records, clock) {
    this.account = account;
    this.records = records;
    this.clock = clock;
    this.device = logicalID(account.id, 'web-device');
  }
  put(kind, identifier, content, date = new Date().toISOString()) {
    const id = identifier.toLowerCase();
    const key = `${kind}:${id}`;
    const old = this.records.get(key);
    if (old?.deleted) return;
    const previous = old ? JSON.parse(old.payload) : null;
    const changed = Object.keys(content).filter(
      (field) =>
        JSON.stringify(previous?.[field]) !== JSON.stringify(content[field]),
    );
    if (old && !changed.length) return;
    const sequence = (this.clock[this.device] || 0) + 1;
    this.clock = { ...this.clock, [this.device]: sequence };
    const fields = { ...old?.fields };
    const stamp = { vector: { ...this.clock }, origin: this.device, sequence };
    for (const field of changed) fields[field] = stamp;
    const version = (old?.version || 0) + 1;
    const metadata = {
      id,
      ownerId: this.account.id,
      workspaceId: this.account.workspace_id,
      version,
      createdAt: previous?.metadata.createdAt || date,
      updatedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    };
    const record = {
      kind,
      recordID: id,
      version,
      payload: JSON.stringify({ ...previous, ...content, metadata }),
      deleted: false,
      vector: { ...this.clock },
      fields,
      origin: this.device,
      sequence,
    };
    this.records.set(key, validateRecord(record, this.account));
  }
  remove(kind, id) {
    const key = `${kind}:${id.toLowerCase()}`;
    const old = this.records.get(key);
    if (old?.deleted) return;
    const sequence = (this.clock[this.device] || 0) + 1;
    this.clock = { ...this.clock, [this.device]: sequence };
    this.records.set(key, {
      kind,
      recordID: id.toLowerCase(),
      version: (old?.version || 0) + 1,
      payload: null,
      deleted: true,
      vector: { ...this.clock },
      fields: old?.fields || {},
      origin: this.device,
      sequence,
    });
  }
}
