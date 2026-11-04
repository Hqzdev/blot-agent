import { AuthError } from "../auth/errors.mjs";
import { digest, validID, equal } from "./security.mjs";

const CHUNK_BYTES = 524288;
const invalid = () => new AuthError("invalid_workspace_backup");
function manifest(row) {
  return { snapshotID: row.id, deviceID: row.device_id, digest: row.digest,
    byteCount: row.byte_count, chunkCount: row.chunk_count };
}

export class WorkspaceBackups {
  #database;
  constructor(database) { this.#database = database; }

  async list(account) {
    const { rows } = await this.#database.query(`SELECT DISTINCT ON (device_id) * FROM blot_workspace_backups
      WHERE owner_id = $1 AND committed ORDER BY device_id, created_at DESC, id DESC`, [account.id]);
    return rows.map(manifest);
  }

  async begin(account, body) {
    if (!validID(body.snapshotID) || !validID(body.deviceID) || typeof body.digest !== "string" || !/^[0-9a-f]{64}$/.test(body.digest)
        || !Number.isInteger(body.byteCount) || body.byteCount < 1 || body.byteCount > 32 * 1024 * 1024
        || body.chunkCount !== Math.ceil(body.byteCount / CHUNK_BYTES)) throw invalid();
    return this.#database.transaction(async tx => {
      await tx.query("SELECT id FROM blot_accounts WHERE id = $1 FOR UPDATE", [account.id]);
      await tx.query("DELETE FROM blot_workspace_backups WHERE owner_id = $1 AND NOT committed AND created_at < now() - interval '1 day'", [account.id]);
      const old = (await tx.query("SELECT * FROM blot_workspace_backups WHERE id = $1", [body.snapshotID])).rows[0];
      if (old) {
        if (old.owner_id !== account.id || old.device_id !== body.deviceID.toLowerCase() || old.digest !== body.digest
            || old.byte_count !== body.byteCount || old.chunk_count !== body.chunkCount) throw invalid();
        return manifest(old);
      }
      const usage = (await tx.query(`SELECT count(*) AS count, COALESCE(sum(byte_count), 0) AS bytes
        FROM blot_workspace_backups WHERE owner_id = $1`, [account.id])).rows[0];
      if (Number(usage.count) >= 32 || Number(usage.bytes) + body.byteCount > 128 * 1024 * 1024) throw new AuthError("workspace_storage_full", 413);
      await tx.query(`INSERT INTO blot_workspace_backups(id, owner_id, device_id, digest, byte_count, chunk_count)
        VALUES ($1, $2, $3, $4, $5, $6)`, [body.snapshotID, account.id, body.deviceID, body.digest, body.byteCount, body.chunkCount]);
      return body;
    });
  }

  async putPart(account, snapshotID, part, body) {
    if (!validID(snapshotID) || !Number.isInteger(part) || part < 0 || part > 63
        || typeof body.data !== "string" || body.data.length > 699052 || !/^[A-Za-z0-9+/]+={0,2}$/.test(body.data)) throw invalid();
    const bytes = Buffer.from(body.data, "base64");
    if (bytes.toString("base64") !== body.data) throw invalid();
    await this.#database.transaction(async tx => {
      const row = (await tx.query("SELECT * FROM blot_workspace_backups WHERE id = $1 AND owner_id = $2 FOR UPDATE", [snapshotID, account.id])).rows[0];
      if (!row || part >= row.chunk_count || bytes.length !== Math.min(CHUNK_BYTES, row.byte_count - part * CHUNK_BYTES)) throw invalid();
      if (row.committed) {
        const saved = (await tx.query("SELECT payload FROM blot_workspace_backup_parts WHERE snapshot_id = $1 AND part = $2", [snapshotID, part])).rows[0];
        if (!saved || !equal(Buffer.from(saved.payload), bytes)) throw invalid();
        return;
      }
      await tx.query(`INSERT INTO blot_workspace_backup_parts(snapshot_id, part, payload) VALUES ($1, $2, $3)
        ON CONFLICT(snapshot_id, part) DO UPDATE SET payload = EXCLUDED.payload`, [snapshotID, part, bytes]);
    });
    return { saved: true };
  }

  async commit(account, snapshotID) {
    if (!validID(snapshotID)) throw invalid();
    return this.#database.transaction(async tx => {
      await tx.query("SELECT id FROM blot_accounts WHERE id = $1 FOR UPDATE", [account.id]);
      const row = (await tx.query("SELECT * FROM blot_workspace_backups WHERE id = $1 AND owner_id = $2 FOR UPDATE", [snapshotID, account.id])).rows[0];
      if (!row) throw invalid();
      if (row.committed) return manifest(row);
      const parts = (await tx.query("SELECT payload FROM blot_workspace_backup_parts WHERE snapshot_id = $1 ORDER BY part", [snapshotID])).rows;
      const bytes = Buffer.concat(parts.map(p => Buffer.from(p.payload)));
      if (parts.length !== row.chunk_count || bytes.length !== row.byte_count || !equal(digest(bytes), row.digest)) throw invalid();
      let snapshot;
      try { snapshot = JSON.parse(bytes.toString("utf8")); } catch { throw invalid(); }
      if (typeof snapshot.ownerID !== "string" || snapshot.ownerID.toLowerCase() !== account.id
          || typeof snapshot.workspaceID !== "string" || snapshot.workspaceID.toLowerCase() !== account.workspace_id
          || typeof snapshot.id !== "string" || snapshot.id.toLowerCase() !== snapshotID.toLowerCase()
          || !Array.isArray(snapshot.records) || typeof snapshot.watermark !== "object" || !snapshot.watermark) throw invalid();
      await tx.query("UPDATE blot_workspace_backups SET committed = true WHERE id = $1", [snapshotID]);
      // Keep the previous committed snapshot for an in-flight reader; pruning happens on the next commit.
      await tx.query(`DELETE FROM blot_workspace_backups WHERE owner_id = $1 AND device_id = $2
        AND committed AND id NOT IN (SELECT id FROM blot_workspace_backups WHERE owner_id = $1
          AND device_id = $2 AND committed ORDER BY created_at DESC, id DESC LIMIT 2)`, [account.id, row.device_id]);
      return manifest(row);
    });
  }

  async part(account, snapshotID, part) {
    if (!validID(snapshotID) || !Number.isInteger(part) || part < 0 || part > 63) throw invalid();
    const { rows } = await this.#database.query(`SELECT p.payload FROM blot_workspace_backup_parts p
      JOIN blot_workspace_backups b ON b.id = p.snapshot_id
      WHERE b.owner_id = $1 AND b.id = $2 AND b.committed AND p.part = $3`, [account.id, snapshotID, part]);
    if (!rows[0]) throw new AuthError("not_found", 404);
    return { data: Buffer.from(rows[0].payload).toString("base64") };
  }
}
