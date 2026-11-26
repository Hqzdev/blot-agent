import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';
import { BlotChatSyncBridge } from '@blot/chat-sync';
import { WorkspaceBackups } from '../../../../landing/lib/accounts/workspace-backups.mjs';
import { verifySharedChatSync } from '../../packages/chat-sync/src/verification.mjs';
import { WebDatabaseMigrator } from '../../packages/database/src/web-migrator.mjs';

const require = createRequire(
  new URL('../../../../landing/package.json', import.meta.url),
);
const { PGlite } = require('@electric-sql/pglite');
const { pgcrypto } = require('@electric-sql/pglite/contrib/pgcrypto');
const account = {
  id: '11111111-1111-4111-a111-111111111111',
  workspace_id: '22222222-2222-4222-a222-222222222222',
};
const chatID = '33333333-3333-4333-a333-333333333333';
const secondChatID = '44444444-4444-4444-a444-444444444444';
const messageID = '55555555-5555-4555-a555-555555555555';

class TestDatabase {
  readonly pg = new PGlite({ extensions: { pgcrypto } });
  async query(sql: string, values: unknown[] = []) {
    return values.length
      ? this.pg.query(sql, values)
      : (await this.pg.exec(sql)).at(-1);
  }
  async transaction<T>(operation: (transaction: TestDatabase) => Promise<T>) {
    await this.query('BEGIN');
    try {
      const result = await operation(this);
      await this.query('COMMIT');
      return result;
    } catch (error) {
      await this.query('ROLLBACK');
      throw error;
    }
  }
  async prepare() {
    await this.query(
      await readFile(
        new URL('../../../../landing/lib/accounts/schema.sql', import.meta.url),
        'utf8',
      ),
    );
    await this.query(
      'INSERT INTO blot_accounts(id,workspace_id,email,name,verified) VALUES ($1,$2,$3,$4,true)',
      [
        account.id,
        account.workspace_id,
        'shared-chat-test@example.org',
        'Sync test',
      ],
    );
    await new WebDatabaseMigrator((sql: string, values?: unknown[]) =>
      this.query(sql, values),
    ).migrate();
  }
}

test('cloud verification rolls back its temporary owner and every chat record', async () => {
  const database = new TestDatabase();
  try {
    await database.prepare();
    await verifySharedChatSync({
      async reserve() {
        return {
          async unsafe(sql: string, values: unknown[] = []) {
            return (await database.query(sql, values)).rows;
          },
          release() {},
        };
      },
    });
    assert.equal(
      Number(
        (
          await database.query(
            'SELECT count(*) AS count FROM public.blot_accounts',
          )
        ).rows[0].count,
      ),
      1,
    );
    assert.equal(
      Number(
        (
          await database.query(
            'SELECT count(*) AS count FROM conversation.chats',
          )
        ).rows[0].count,
      ),
      0,
    );
    assert.equal(
      Number(
        (
          await database.query(
            'SELECT count(*) AS count FROM public.blot_workspace_backups',
          )
        ).rows[0].count,
      ),
      0,
    );
  } finally {
    await database.pg.close();
  }
});

async function seedWeb(database: TestDatabase) {
  await database.query(
    "INSERT INTO conversation.chats(id,user_id,title,created_at) VALUES ($1,$2,'From web','2026-11-15T10:00:00Z'),($3,$2,'Second web chat','2026-11-15T10:00:01Z')",
    [chatID, account.id, secondChatID],
  );
  await database.query(
    "INSERT INTO conversation.messages(id,chat_id,role,parts,created_at) VALUES ($1,$2,'user',$3::jsonb,'2026-11-15T10:00:02Z')",
    [
      messageID,
      chatID,
      JSON.stringify([{ type: 'text', text: 'Written in the web' }]),
    ],
  );
  await database.query(
    "INSERT INTO conversation.messages(id,chat_id,role,parts,created_at) VALUES ($1,$2,'assistant',$3::jsonb,'2026-11-15T10:00:03Z')",
    [
      '77777777-7777-4777-a777-777777777777',
      chatID,
      JSON.stringify([{ type: 'text', text: 'Web assistant answer' }]),
    ],
  );
}

async function upload(
  database: TestDatabase,
  snapshot: {
    id: string;
    ownerID: string;
    workspaceID: string;
    watermark: unknown;
    records: unknown[];
  },
  deviceID: string,
) {
  const bytes = Buffer.from(JSON.stringify(snapshot));
  const { createHash } = await import('node:crypto');
  const backups = new WorkspaceBackups(database);
  await backups.begin(account, {
    snapshotID: snapshot.id,
    deviceID,
    digest: createHash('sha256').update(bytes).digest('hex'),
    byteCount: bytes.length,
    chunkCount: Math.ceil(bytes.length / 524288),
  });
  for (let part = 0; part * 524288 < bytes.length; part++)
    await backups.putPart(account, snapshot.id, part, {
      data: bytes
        .subarray(part * 524288, (part + 1) * 524288)
        .toString('base64'),
    });
  await backups.commit(account, snapshot.id);
}

test('web history produces stable native snapshots, preserves separate chats and propagates deletion', async () => {
  const database = new TestDatabase();
  try {
    await database.prepare();
    await seedWeb(database);
    const bridge = new BlotChatSyncBridge(database);
    await bridge.synchronize(account.id);
    const backups = new WorkspaceBackups(database);
    const first = (await backups.list(account))[0];
    const bytes = Buffer.from(
      (await backups.part(account, first.snapshotID, 0)).data,
      'base64',
    );
    const snapshot = JSON.parse(bytes.toString());
    assert.equal(
      snapshot.records.filter(
        (record: { kind: string }) => record.kind === 'Conversation',
      ).length,
      2,
    );
    const profiles = snapshot.records.filter(
      (record: { kind: string }) => record.kind === 'AgentProfile',
    );
    assert.equal(
      new Set(profiles.map((record: { recordID: string }) => record.recordID))
        .size,
      2,
    );
    if (process.env.BLOT_WRITE_WEB_CHAT_FIXTURE)
      await writeFile(
        process.env.BLOT_WRITE_WEB_CHAT_FIXTURE,
        `${JSON.stringify(snapshot, null, 2)}\n`,
      );
    await bridge.synchronize(account.id);
    assert.equal(
      (await backups.list(account))[0].snapshotID,
      first.snapshotID,
      'Unchanged history must not generate another snapshot',
    );
    assert.equal(
      Number(
        (
          await database.query(
            'SELECT count(*) AS count FROM blot_web.chat_events',
          )
        ).rows[0].count,
      ),
      0,
    );
    await database.query('DELETE FROM conversation.chats WHERE id=$1', [
      chatID,
    ]);
    await bridge.synchronize(account.id);
    const after = (await backups.list(account))[0];
    const deleted = JSON.parse(
      Buffer.from(
        (await backups.part(account, after.snapshotID, 0)).data,
        'base64',
      ).toString(),
    );
    assert.ok(
      deleted.records.some(
        (record: { kind: string; recordID: string; deleted: boolean }) =>
          record.kind === 'Conversation' &&
          record.recordID === chatID &&
          record.deleted,
      ),
    );
    assert.ok(
      deleted.records.some(
        (record: { kind: string; recordID: string; deleted: boolean }) =>
          record.kind === 'Message' &&
          record.recordID === messageID &&
          record.deleted,
      ),
    );
    const stale = { ...snapshot, id: randomUUID() };
    await upload(database, stale, randomUUID());
    await bridge.synchronize(account.id);
    assert.equal(
      (
        await database.query('SELECT id FROM conversation.chats WHERE id=$1', [
          chatID,
        ])
      ).rows.length,
      0,
      'Old offline replicas cannot resurrect deleted chats',
    );
  } finally {
    await database.pg.close();
  }
});

test('an actual Swift replica reply is imported into web history without duplicates or cross-account access', async () => {
  const database = new TestDatabase();
  try {
    await database.prepare();
    await seedWeb(database);
    const bridge = new BlotChatSyncBridge(database);
    await bridge.synchronize(account.id);
    const snapshot = JSON.parse(
      await readFile(
        new URL(
          '../../packages/chat-sync/fixtures/native-snapshot.json',
          import.meta.url,
        ),
        'utf8',
      ),
    );
    const device = snapshot.records.find(
      (record: { payload: string | null }) =>
        record.payload &&
        JSON.parse(record.payload).content === 'Reply from iPhone',
    ).origin;
    await upload(database, snapshot, device);
    await bridge.synchronize(account.id);
    await bridge.synchronize(account.id);
    const rows = (
      await database.query(
        'SELECT parts FROM conversation.messages WHERE chat_id=$1 ORDER BY created_at,id',
        [chatID],
      )
    ).rows;
    assert.equal(rows.length, 3);
    assert.ok(
      rows.some(
        (row: { parts: { text: string }[] }) =>
          row.parts[0].text === 'Reply from iPhone',
      ),
    );
    const other = { id: randomUUID(), workspace_id: randomUUID() };
    await database.query(
      'INSERT INTO blot_accounts(id,workspace_id,email,name,verified) VALUES ($1,$2,$3,$4,true)',
      [other.id, other.workspace_id, 'other-sync@example.org', 'Other'],
    );
    assert.equal((await new WorkspaceBackups(database).list(other)).length, 0);
    const foreign = structuredClone(snapshot);
    foreign.id = randomUUID();
    foreign.ownerID = other.id;
    foreign.workspaceID = other.workspace_id;
    const bytes = Buffer.from(JSON.stringify(foreign));
    const { createHash } = await import('node:crypto');
    const backups = new WorkspaceBackups(database);
    await backups.begin(other, {
      snapshotID: foreign.id,
      deviceID: randomUUID(),
      digest: createHash('sha256').update(bytes).digest('hex'),
      byteCount: bytes.length,
      chunkCount: 1,
    });
    await backups.putPart(other, foreign.id, 0, {
      data: bytes.toString('base64'),
    });
    await backups.commit(other, foreign.id);
    await assert.rejects(bridge.synchronize(other.id), /identity mismatch/);
    assert.equal(
      (
        await database.query(
          'SELECT user_id FROM conversation.chats WHERE id=$1',
          [chatID],
        )
      ).rows[0].user_id,
      account.id,
    );
    await database.query('DELETE FROM blot_accounts WHERE id=$1', [account.id]);
    assert.equal(
      (
        await database.query(
          'SELECT id FROM conversation.chats WHERE user_id=$1',
          [account.id],
        )
      ).rows.length,
      0,
    );
  } finally {
    await database.pg.close();
  }
});
