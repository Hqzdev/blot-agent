import { randomUUID } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { AuthError } from "../auth/errors.mjs";
import { emailAddress, equal, validToken } from "./security.mjs";

const keys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"), { timeoutDuration: 10_000 });
export class GoogleAccountIdentity {
  #audience;
  #keys;
  constructor(audience, signingKeys = keys) { this.#audience = audience; this.#keys = signingKeys; }
  async verify(idToken, nonce) {
    if (!this.#audience) throw new AuthError("google_unconfigured", 503);
    if (typeof idToken !== "string" || idToken.length > 16_384 || !validToken(nonce)) throw new AuthError("google_identity_invalid", 401);
    try {
      const { payload } = await jwtVerify(idToken, this.#keys, { audience: this.#audience,
        issuer: ["https://accounts.google.com", "accounts.google.com"], algorithms: ["RS256"], requiredClaims: ["exp", "iat", "sub"] });
      if (payload.email_verified !== true || typeof payload.nonce !== "string" || !equal(payload.nonce, nonce)
          || typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 255) throw new Error();
      const email = emailAddress(payload.email);
      const name = typeof payload.name === "string" && payload.name.trim() ? payload.name.trim().slice(0, 200) : email;
      return { subject: payload.sub, email, name };
    } catch (error) {
      if (error.code === "ERR_JWKS_TIMEOUT" || error instanceof TypeError && error.message === "fetch failed") throw new AuthError("google_unavailable", 503);
      throw new AuthError("google_identity_invalid", 401);
    }
  }
}

export class GoogleAccounts {
  #database;
  #identity;
  #sessions;
  constructor(database, identity, sessions) { this.#database = database; this.#identity = identity; this.#sessions = sessions; }
  async login({ idToken, nonce }) {
    const identity = await this.#identity.verify(idToken, nonce);
    return this.#database.transaction(async tx => {
      await tx.query("SELECT pg_advisory_xact_lock(hashtext($1))", [identity.email]);
      let account = (await tx.query("SELECT * FROM blot_accounts WHERE google_subject = $1 AND verified", [identity.subject])).rows[0];
      if (!account) {
        if ((await tx.query("SELECT id FROM blot_accounts WHERE email = $1", [identity.email])).rows[0]) throw new AuthError("google_link_required", 409);
        account = (await tx.query(`INSERT INTO blot_accounts(id, workspace_id, email, name, google_subject, verified)
          VALUES ($1, $2, $3, $4, $5, true) RETURNING *`,
        [randomUUID(), randomUUID(), identity.email, identity.name, identity.subject])).rows[0];
      }
      return this.#sessions.create(tx, account);
    });
  }
}
