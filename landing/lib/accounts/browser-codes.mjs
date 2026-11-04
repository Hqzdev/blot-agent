import { createHash } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { digest, equal, randomToken, validToken } from "./security.mjs";

const CLIENTS = { "blot-ios": "blot-agent-ios:/oauth/account", "blot-macos": "blot-agent-macos:/oauth/account" };
const invalid = () => new AuthError("browser_authorization_invalid", 401);
function validateClient(body) {
  if (typeof body.clientID !== "string" || !Object.hasOwn(CLIENTS, body.clientID)
      || body.redirectURI !== CLIENTS[body.clientID]) throw invalid();
}

export class BrowserAuthorizationCodes {
  #database;
  #sessions;
  constructor(database, sessions) { this.#database = database; this.#sessions = sessions; }
  async issue(body, accessToken) {
    validateClient(body);
    if (!validToken(body.codeChallenge)) throw invalid();
    const code = randomToken(), expiresAt = new Date(Date.now() + 60_000).toISOString();
    await this.#database.transaction(async tx => {
      const account = await this.#sessions.require(accessToken, tx);
      await tx.query("SELECT id FROM blot_sessions WHERE id = $1 AND NOT revoked FOR UPDATE", [account.session_id]);
      // Recheck after the lock in case logout completed while it was being acquired.
      await this.#sessions.require(accessToken, tx);
      await tx.query(`INSERT INTO blot_browser_codes(code_hash, session_id, owner_id, client_id, redirect_uri, challenge, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [digest(code), account.session_id, account.id, body.clientID, body.redirectURI, body.codeChallenge, expiresAt]);
    });
    return { code, expiresAt };
  }
  async exchange(body) {
    validateClient(body);
    if (!validToken(body.code) || typeof body.codeVerifier !== "string" || !/^[A-Za-z0-9._~-]{43,128}$/.test(body.codeVerifier)) throw invalid();
    const challenge = createHash("sha256").update(body.codeVerifier).digest("base64url");
    return this.#database.transaction(async tx => {
      const { rows } = await tx.query(`SELECT b.*, a.workspace_id FROM blot_browser_codes b
        JOIN blot_sessions s ON s.id = b.session_id JOIN blot_accounts a ON a.id = b.owner_id
        WHERE b.code_hash = $1 AND b.client_id = $2 AND b.redirect_uri = $3
        AND b.expires_at > now() AND NOT s.revoked AND a.verified FOR UPDATE OF b, s`,
      [digest(body.code), body.clientID, body.redirectURI]);
      const saved = rows[0];
      if (!saved || !equal(saved.challenge, challenge)) throw invalid();
      await tx.query("DELETE FROM blot_browser_codes WHERE code_hash = $1", [digest(body.code)]);
      return this.#sessions.create(tx, { id: saved.owner_id, workspace_id: saved.workspace_id });
    });
  }
}
