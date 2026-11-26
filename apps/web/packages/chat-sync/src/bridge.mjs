import { createHash, randomUUID } from 'node:crypto';
export { PostgresBridgeDatabase } from './postgres-database.mjs';
import {
  NativeChatProjection,
  conversationAliases,
  messagePositions,
} from './native-projection.mjs';
import {
  WebReplicaEditor,
  mergeClock,
  mergeRecord,
  stableJSON,
  validClock,
  validateRecord,
} from './replica.mjs';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const chunkBytes = 524288;

/** The database supplies a transaction and query interface; no platform or UI dependencies. */
export class BlotChatSyncBridge {
  constructor(database) {
    this.database = database;
  }

  async synchronize(ownerID) {
    if (typeof ownerID !== 'string') return;
    const available = await this.database.query(
      "SELECT to_regclass('blot_web.chat_replica_records') AS ready",
    );
    if (!available.rows[0].ready) return;
    return this.database.transaction(async (tx) => {
      const account = (
        await tx.query(
          'SELECT id,workspace_id FROM public.blot_accounts WHERE id=$1 FOR UPDATE',
          [ownerID],
        )
      ).rows[0];
      if (!account) return;
      const saved = (
        await tx.query(
          'SELECT * FROM blot_web.chat_replica_state WHERE owner_id=$1',
          [account.id],
        )
      ).rows[0];
      const rows = (
        await tx.query(
          'SELECT record FROM blot_web.chat_replica_records WHERE owner_id=$1',
          [account.id],
        )
      ).rows;
      const records = new Map(
        rows.map((row) => [
          `${row.record.kind}:${row.record.recordID}`,
          row.record,
        ]),
      );
      const editor = new WebReplicaEditor(account, records, saved?.clock || {});
      const events = (
        await tx.query(
          'SELECT * FROM blot_web.chat_events WHERE owner_id=$1 ORDER BY id',
          [account.id],
        )
      ).rows;
      const projection = new NativeChatProjection(editor);
      for (const event of events) projection.applyEvent(event);
      await this.importBackups(tx, account, editor);
      let snapshotID = saved?.snapshot_id;
      if (records.size) {
        const ordered = [...records.values()].sort((a, b) =>
          (a.kind + a.recordID).localeCompare(b.kind + b.recordID),
        );
        const fingerprint = digest(
          Buffer.from(stableJSON({ records: ordered, clock: editor.clock })),
        );
        if (fingerprint !== saved?.fingerprint) {
          await this.materialize(tx, account, editor.records);
          snapshotID = await this.publish(tx, account, editor, ordered);
          await tx.query(
            `INSERT INTO blot_web.chat_replica_state(owner_id,clock,fingerprint,snapshot_id) VALUES ($1,$2::jsonb,$3,$4)
          ON CONFLICT(owner_id) DO UPDATE SET clock=EXCLUDED.clock,fingerprint=EXCLUDED.fingerprint,snapshot_id=EXCLUDED.snapshot_id`,
            [account.id, JSON.stringify(editor.clock), fingerprint, snapshotID],
          );
          await tx.query(
            `INSERT INTO blot_web.chat_replica_records(owner_id,kind,record_id,record)
          SELECT $1,x->>'kind',(x->>'recordID')::uuid,x FROM jsonb_array_elements($2::jsonb) x
          ON CONFLICT(owner_id,kind,record_id) DO UPDATE SET record=EXCLUDED.record`,
            [account.id, JSON.stringify(ordered)],
          );
        }
      }
      if (events.length)
        await tx.query(
          'DELETE FROM blot_web.chat_events WHERE owner_id=$1 AND id <= $2',
          [account.id, events.at(-1).id],
        );
      return { records: records.size, snapshotID };
    });
  }

  async importBackups(tx, account, editor) {
    const pending = (
      await tx.query(
        `SELECT b.* FROM (
      SELECT DISTINCT ON(device_id) * FROM public.blot_workspace_backups WHERE owner_id=$1 AND committed ORDER BY device_id,created_at DESC,id DESC
      ) b LEFT JOIN blot_web.chat_replica_imports i ON i.snapshot_id=b.id WHERE i.snapshot_id IS NULL AND b.device_id <> $2`,
        [account.id, editor.device],
      )
    ).rows;
    for (const backup of pending) {
      const parts = (
        await tx.query(
          "SELECT encode(payload,'base64') AS payload FROM public.blot_workspace_backup_parts WHERE snapshot_id=$1 ORDER BY part",
          [backup.id],
        )
      ).rows;
      const bytes = Buffer.concat(
        parts.map((part) => Buffer.from(part.payload, 'base64')),
      );
      if (bytes.length !== backup.byte_count || digest(bytes) !== backup.digest)
        throw new Error('Invalid committed chat snapshot');
      const snapshot = JSON.parse(bytes.toString('utf8'));
      if (
        snapshot.ownerID?.toLowerCase() !== account.id ||
        snapshot.workspaceID?.toLowerCase() !== account.workspace_id ||
        !validClock(snapshot.watermark) ||
        !Array.isArray(snapshot.records)
      )
        throw new Error('Invalid chat snapshot identity');
      for (const value of snapshot.records) {
        const incoming = validateRecord(value, account);
        if (!incoming) continue;
        if (
          !Object.entries(incoming.vector).every(
            ([id, sequence]) => (snapshot.watermark[id] || 0) >= sequence,
          )
        )
          throw new Error('Invalid chat snapshot clock');
        const key = `${incoming.kind}:${incoming.recordID}`;
        editor.records.set(key, mergeRecord(editor.records.get(key), incoming));
      }
      editor.clock = mergeClock(editor.clock, snapshot.watermark);
      await tx.query(
        'INSERT INTO blot_web.chat_replica_imports(snapshot_id,owner_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
        [backup.id, account.id],
      );
    }
  }

  async materialize(tx, account, records) {
    const aliases = conversationAliases(records);
    const positions = messagePositions(records, aliases);
    const chats = [];
    const messages = [];
    const removedChats = [];
    const removedMessages = [];
    for (const record of records.values()) {
      if (record.deleted) {
        if (record.kind === 'Conversation') removedChats.push(record.recordID);
        if (record.kind === 'Message') removedMessages.push(record.recordID);
        continue;
      }
      const value = JSON.parse(record.payload);
      if (record.kind === 'Conversation') {
        if (aliases.get(record.recordID) !== record.recordID) {
          removedChats.push(record.recordID);
          continue;
        }
        chats.push({
          id: record.recordID,
          title: value.title,
          created_at: value.metadata.createdAt,
          updated_at: value.metadata.updatedAt,
        });
      }
      if (record.kind === 'Message') {
        const chatID = aliases.get(value.conversationId.toLowerCase());
        if (!chatID) continue;
        messages.push({
          id: record.recordID,
          chat_id: chatID,
          role:
            value.role === 'USER'
              ? 'user'
              : value.role === 'SYSTEM'
                ? 'system'
                : 'assistant',
          parts: [{ type: 'text', text: value.content }],
          created_at: value.metadata.createdAt,
          position: positions.get(record.recordID),
        });
      }
    }
    await tx.query("SELECT set_config('blot.sync_projection','on',true)");
    if (chats.length) {
      const collision = await tx.query(
        `SELECT c.id FROM conversation.chats c JOIN jsonb_array_elements($1::jsonb) x ON c.id=(x->>'id')::uuid WHERE c.user_id <> $2 LIMIT 1`,
        [JSON.stringify(chats), account.id],
      );
      if (collision.rows.length)
        throw new Error('Chat ID belongs to another account');
      await tx.query(
        `INSERT INTO conversation.chats(id,user_id,title,created_at,updated_at)
        SELECT x.id,$1,x.title,x.created_at,x.updated_at FROM jsonb_to_recordset($2::jsonb) AS x(id uuid,title text,created_at timestamptz,updated_at timestamptz)
        ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,updated_at=greatest(conversation.chats.updated_at,EXCLUDED.updated_at) WHERE conversation.chats.user_id=$1`,
        [account.id, JSON.stringify(chats)],
      );
    }
    if (messages.length) {
      const collision = await tx.query(
        `SELECT m.id FROM conversation.messages m JOIN jsonb_array_elements($1::jsonb) x ON m.id=(x->>'id')::uuid JOIN conversation.chats c ON c.id=m.chat_id WHERE c.user_id <> $2 LIMIT 1`,
        [JSON.stringify(messages), account.id],
      );
      if (collision.rows.length)
        throw new Error('Message ID belongs to another account');
      await tx.query(
        `INSERT INTO conversation.messages(id,chat_id,role,parts,attachments,created_at)
        SELECT x.id,x.chat_id,x.role,x.parts,'[]'::jsonb,x.created_at FROM jsonb_to_recordset($2::jsonb) AS x(id uuid,chat_id uuid,role text,parts jsonb,created_at timestamptz)
        JOIN conversation.chats c ON c.id=x.chat_id AND c.user_id=$1
        ON CONFLICT(id) DO UPDATE SET chat_id=EXCLUDED.chat_id,role=EXCLUDED.role,
          parts=CASE WHEN conversation.messages.parts=EXCLUDED.parts OR
            (SELECT string_agg(p->>'text',E'\n' ORDER BY n) FROM jsonb_array_elements(conversation.messages.parts) WITH ORDINALITY AS a(p,n) WHERE p->>'type'='text') = (EXCLUDED.parts->0->>'text')
            THEN conversation.messages.parts ELSE EXCLUDED.parts END`,
        [account.id, JSON.stringify(messages)],
      );
      await tx.query(
        `INSERT INTO blot_web.message_order(message_id,position) SELECT (x->>'id')::uuid,(x->>'position')::bigint FROM jsonb_array_elements($1::jsonb) x
        ON CONFLICT(message_id) DO UPDATE SET position=EXCLUDED.position`,
        [JSON.stringify(messages)],
      );
    }
    if (removedMessages.length)
      await tx.query(
        'DELETE FROM conversation.messages m USING conversation.chats c WHERE m.chat_id=c.id AND c.user_id=$1 AND m.id=ANY($2::uuid[])',
        [account.id, removedMessages],
      );
    if (removedChats.length)
      await tx.query(
        'DELETE FROM conversation.chats WHERE user_id=$1 AND id=ANY($2::uuid[])',
        [account.id, removedChats],
      );
    await tx.query("SELECT set_config('blot.sync_projection','off',true)");
  }

  async publish(tx, account, editor, records) {
    const id = randomUUID();
    const snapshot = {
      id,
      ownerID: account.id,
      workspaceID: account.workspace_id,
      watermark: editor.clock,
      relayCursor: 0,
      records,
    };
    const bytes = Buffer.from(JSON.stringify(snapshot));
    if (bytes.length > 32 * 1024 * 1024)
      throw new Error('Shared chat snapshot exceeds the native sync limit');
    await tx.query(
      'INSERT INTO public.blot_workspace_backups(id,owner_id,device_id,digest,byte_count,chunk_count,committed,created_at) VALUES ($1,$2,$3,$4,$5,$6,true,clock_timestamp())',
      [
        id,
        account.id,
        editor.device,
        digest(bytes),
        bytes.length,
        Math.ceil(bytes.length / chunkBytes),
      ],
    );
    for (let part = 0; part * chunkBytes < bytes.length; part++)
      await tx.query(
        'INSERT INTO public.blot_workspace_backup_parts(snapshot_id,part,payload) VALUES ($1,$2,$3)',
        [id, part, bytes.subarray(part * chunkBytes, (part + 1) * chunkBytes)],
      );
    await tx.query(
      `DELETE FROM public.blot_workspace_backups WHERE owner_id=$1 AND device_id=$2 AND id NOT IN
      (SELECT id FROM public.blot_workspace_backups WHERE owner_id=$1 AND device_id=$2 AND committed ORDER BY created_at DESC,id DESC LIMIT 2)`,
      [account.id, editor.device],
    );
    return id;
  }
}
