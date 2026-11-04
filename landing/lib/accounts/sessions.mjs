import { randomUUID } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { digest, randomToken, validToken } from "./security.mjs";

export class AccountSessions {
  #database;
  constructor(database) { this.#database = database; }

  async create(tx, account) {
    const sessionID = randomUUID(), accessToken = randomToken(), refreshToken = randomToken();
    const expiresAt = new Date(Date.now() + 900_000).toISOString();
    await tx.query(`INSERT INTO blot_sessions(id, owner_id, access_hash, refresh_hash, access_expires, refresh_expires)
      VALUES ($1, $2, $3, $4, $5, now() + interval '30 days')`,
    [sessionID, account.id, digest(accessToken), digest(refreshToken), expiresAt]);
    return { sessionID, accessToken, refreshToken, expiresAt, ownerID: account.id,
      workspaceID: account.workspace_id, deviceID: null, bootstrapAllowed: true };
  }

  async require(accessToken, tx = this.#database) {
    if (!validToken(accessToken)) throw new AuthError("session_required", 401);
    const { rows } = await tx.query(`SELECT a.*, s.id AS session_id FROM blot_sessions s
      JOIN blot_accounts a ON a.id = s.owner_id
      WHERE s.access_hash = $1 AND NOT s.revoked AND s.access_expires > now() AND a.verified`, [digest(accessToken)]);
    if (!rows[0]) throw new AuthError("session_expired", 401);
    return rows[0];
  }

  async refresh(refreshToken) {
    if (!validToken(refreshToken)) throw new AuthError("session_expired", 401);
    return this.#database.transaction(async tx => {
      const { rows } = await tx.query(`SELECT s.id AS session_id, a.* FROM blot_sessions s
        JOIN blot_accounts a ON a.id = s.owner_id WHERE s.refresh_hash = $1 AND NOT s.revoked
        AND s.refresh_expires > now() AND a.verified FOR UPDATE OF s`, [digest(refreshToken)]);
      const account = rows[0];
      if (!account) throw new AuthError("session_expired", 401);
      const accessToken = randomToken(), rotatedRefresh = randomToken(), expiresAt = new Date(Date.now() + 900_000).toISOString();
      await tx.query("UPDATE blot_sessions SET access_hash = $1, refresh_hash = $2, access_expires = $3 WHERE id = $4",
        [digest(accessToken), digest(rotatedRefresh), expiresAt, account.session_id]);
      return { sessionID: account.session_id, accessToken, refreshToken: rotatedRefresh, expiresAt,
        ownerID: account.id, workspaceID: account.workspace_id, deviceID: null, bootstrapAllowed: true };
    });
  }

  async logout(account, all = false) {
    await this.#database.query(all
      ? "UPDATE blot_sessions SET revoked = true WHERE owner_id = $1"
      : "UPDATE blot_sessions SET revoked = true WHERE owner_id = $1 AND id = $2",
    all ? [account.id] : [account.id, account.session_id]);
  }
}
