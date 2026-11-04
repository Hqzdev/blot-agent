import { randomUUID } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { emailAddress, passwordValue } from "./security.mjs";

export class Accounts {
  #database;
  #passwords;
  #challenges;
  #sessions;
  constructor({ database, passwords, challenges, sessions }) {
    this.#database = database; this.#passwords = passwords; this.#challenges = challenges; this.#sessions = sessions;
  }

  async register({ email: address, password, name }) {
    const email = emailAddress(address);
    passwordValue(password);
    if (typeof name !== "string" || !name.trim() || name.length > 200) throw new AuthError("invalid_name");
    const hash = await this.#passwords.hash(password);
    const { rows } = await this.#database.query(`INSERT INTO blot_accounts(id, workspace_id, email, name, password_hash)
      VALUES ($1, $2, $3, $4, $5) ON CONFLICT(email) DO UPDATE SET email = EXCLUDED.email RETURNING *`,
    [randomUUID(), randomUUID(), email, name.trim(), hash]);
    await this.#challenges.send(rows[0], "verify", { hash, name: name.trim() });
    return null;
  }

  async verify({ email, code }) {
    return this.#challenges.consume(emailAddress(email), "verify", code, async (tx, challenge) => {
      if (!challenge.verified) await tx.query("UPDATE blot_accounts SET password_hash = $1, name = $2, verified = true WHERE id = $3",
        [challenge.registration_hash, challenge.registration_name, challenge.owner_id]);
      return this.#sessions.create(tx, { id: challenge.owner_id, workspace_id: challenge.workspace_id });
    });
  }

  async login({ email, password }) {
    email = emailAddress(email); passwordValue(password);
    const { rows } = await this.#database.query("SELECT * FROM blot_accounts WHERE email = $1", [email]);
    const account = rows[0];
    if (!await this.#passwords.matches(password, account?.password_hash)) throw new AuthError("wrong_credentials", 401);
    if (!account.verified) throw new AuthError("email_unverified", 403);
    return this.#database.transaction(async tx => {
      // Password reset and login serialize on the account; a stale password cannot mint a new session.
      const current = (await tx.query("SELECT * FROM blot_accounts WHERE id = $1 FOR UPDATE", [account.id])).rows[0];
      if (!current?.verified || current.password_hash !== account.password_hash) throw new AuthError("wrong_credentials", 401);
      return this.#sessions.create(tx, current);
    });
  }

  async requestReset({ email }) {
    email = emailAddress(email);
    const { rows } = await this.#database.query("SELECT * FROM blot_accounts WHERE email = $1 AND verified", [email]);
    if (rows[0]) {
      try { await this.#challenges.send(rows[0], "reset"); }
      catch (error) {
        if (!(error instanceof AuthError) || error.status !== 503) throw error;
      }
    }
    return null;
  }

  async reset({ email, code, password }) {
    email = emailAddress(email); passwordValue(password);
    const hash = await this.#passwords.hash(password);
    return this.#challenges.consume(email, "reset", code, async (tx, challenge) => {
      await tx.query("UPDATE blot_accounts SET password_hash = $1 WHERE id = $2", [hash, challenge.owner_id]);
      await tx.query("UPDATE blot_sessions SET revoked = true WHERE owner_id = $1", [challenge.owner_id]);
      return null;
    });
  }

  profile(account) { return { id: account.id, email: account.email, name: account.name, verified: account.verified }; }
}
