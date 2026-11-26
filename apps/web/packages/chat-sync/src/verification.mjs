import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { BlotChatSyncBridge } from './bridge.mjs';

/** Uses fresh IDs and rolls back the entire check, including the temporary owner. */
export async function verifySharedChatSync(client) {
  const connection = await client.reserve();
  const query = async (sql, values = []) => ({
    rows: await connection.unsafe(sql, values),
  });
  const database = { query, transaction: (operation) => operation({ query }) };
  const owner = randomUUID();
  const workspace = randomUUID();
  const chat = randomUUID();
  const message = randomUUID();
  await connection.unsafe('BEGIN');
  try {
    await query(
      'INSERT INTO public.blot_accounts(id,workspace_id,email,name,verified) VALUES ($1,$2,$3,$4,true)',
      [
        owner,
        workspace,
        `sync-check-${owner}@example.org`,
        'Temporary sync check',
      ],
    );
    await query(
      'INSERT INTO conversation.chats(id,user_id,title) VALUES ($1,$2,$3)',
      [chat, owner, 'Shared history verification'],
    );
    await query(
      "INSERT INTO conversation.messages(id,chat_id,role,parts) VALUES ($1,$2,'user',$3::jsonb)",
      [
        message,
        chat,
        JSON.stringify([{ type: 'text', text: 'Written in the web' }]),
      ],
    );
    const bridge = new BlotChatSyncBridge(database);
    const created = await bridge.synchronize(owner);
    const encoded = (
      await query(
        "SELECT encode(payload,'base64') AS payload FROM public.blot_workspace_backup_parts WHERE snapshot_id=$1 ORDER BY part",
        [created.snapshotID],
      )
    ).rows;
    const outbound = JSON.parse(
      Buffer.concat(
        encoded.map((part) => Buffer.from(part.payload, 'base64')),
      ).toString(),
    );
    assert.ok(
      outbound.records.some(
        (record) => record.recordID === chat && record.kind === 'Conversation',
      ),
    );
    const fixture = JSON.parse(
      await readFile(
        new URL('../fixtures/native-snapshot.json', import.meta.url),
        'utf8',
      ),
    );
    const native = fixture.records.find(
      (record) =>
        record.kind === 'Message' &&
        JSON.parse(record.payload).content === 'Reply from iPhone',
    );
    const incoming = structuredClone(native);
    incoming.recordID = randomUUID();
    incoming.version = 1;
    incoming.vector = {
      ...outbound.watermark,
      [incoming.origin.toLowerCase()]: incoming.sequence,
    };
    const payload = JSON.parse(incoming.payload);
    payload.metadata = {
      ...payload.metadata,
      id: incoming.recordID,
      ownerId: owner,
      workspaceId: workspace,
      version: 1,
    };
    payload.conversationId = chat;
    payload.commandId = incoming.recordID;
    payload.position = 2;
    incoming.payload = JSON.stringify(payload);
    incoming.fields = Object.fromEntries(
      Object.keys(payload)
        .filter((key) => key !== 'metadata')
        .map((key) => [
          key,
          {
            origin: incoming.origin,
            sequence: incoming.sequence,
            vector: incoming.vector,
          },
        ]),
    );
    const snapshot = {
      ...outbound,
      id: randomUUID(),
      watermark: incoming.vector,
      records: [...outbound.records, incoming],
    };
    const publish = async (data) => {
      const bytes = Buffer.from(JSON.stringify(data));
      await query(
        'INSERT INTO public.blot_workspace_backups(id,owner_id,device_id,digest,byte_count,chunk_count,committed,created_at) VALUES ($1,$2,$3,$4,$5,1,true,clock_timestamp())',
        [
          data.id,
          owner,
          incoming.origin,
          createHash('sha256').update(bytes).digest('hex'),
          bytes.length,
        ],
      );
      await query(
        'INSERT INTO public.blot_workspace_backup_parts(snapshot_id,part,payload) VALUES ($1,0,$2)',
        [data.id, bytes],
      );
    };
    await publish(snapshot);
    await bridge.synchronize(owner);
    const restored = (
      await query('SELECT parts FROM conversation.messages WHERE chat_id=$1', [
        chat,
      ])
    ).rows;
    assert.equal(restored.length, 2);
    assert.ok(
      restored.some((row) => row.parts[0].text === 'Reply from iPhone'),
    );
    const stable = await bridge.synchronize(owner);
    assert.equal(
      stable.snapshotID,
      (await bridge.synchronize(owner)).snapshotID,
    );
    await query('DELETE FROM conversation.chats WHERE id=$1 AND user_id=$2', [
      chat,
      owner,
    ]);
    await bridge.synchronize(owner);
    await publish({ ...snapshot, id: randomUUID() });
    await bridge.synchronize(owner);
    assert.equal(
      (await query('SELECT id FROM conversation.chats WHERE id=$1', [chat]))
        .rows.length,
      0,
    );
    console.log(
      'Shared chat synchronization passed: web → Apple snapshot → native reply → web; duplicate replay and stale deletion checked; transaction rolled back',
    );
  } finally {
    await connection.unsafe('ROLLBACK');
    connection.release();
  }
}
