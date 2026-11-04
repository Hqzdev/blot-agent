import { randomUUID } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { equal } from "./security.mjs";

export class AccountEmailChallenges {
  #database;
  #security;
  #email;
  #rates;
  constructor({ database, security, email, rates }) {
    this.#database = database; this.#security = security; this.#email = email; this.#rates = rates;
  }

  async send(account, purpose, registration = {}) {
    await this.#rates.check(`email:${purpose}:${account.id}`, 1, 60);
    const id = randomUUID(), code = this.#security.code();
    await this.#database.query(`INSERT INTO blot_email_challenges
      (id, owner_id, purpose, code_hash, expires_at, registration_hash, registration_name)
      VALUES ($1, $2, $3, $4, now() + interval '10 minutes', $5, $6)
      ON CONFLICT(owner_id, purpose) DO UPDATE SET id = EXCLUDED.id, code_hash = EXCLUDED.code_hash,
        expires_at = EXCLUDED.expires_at, attempts = 0,
        registration_hash = EXCLUDED.registration_hash, registration_name = EXCLUDED.registration_name`,
    [id, account.id, purpose, this.#security.hash(id, code), registration.hash || null, registration.name || null]);
    try { await this.#email.sendCode(account.email, code, purpose); }
    catch (error) {
      await this.#database.query("DELETE FROM blot_email_challenges WHERE id = $1", [id]);
      throw error;
    }
  }

  async consume(email, purpose, code, accepted) {
    if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) throw new AuthError("code_expired_or_invalid");
    const result = await this.#database.transaction(async tx => {
      const { rows } = await tx.query(`SELECT c.*, a.workspace_id, a.verified, a.email FROM blot_email_challenges c
        JOIN blot_accounts a ON a.id = c.owner_id WHERE a.email = $1 AND c.purpose = $2 FOR UPDATE OF c, a`, [email, purpose]);
      const challenge = rows[0];
      if (!challenge || challenge.attempts >= 5 || challenge.expires_at.getTime() <= Date.now()) return null;
      await tx.query("UPDATE blot_email_challenges SET attempts = attempts + 1 WHERE id = $1", [challenge.id]);
      if (!equal(challenge.code_hash, this.#security.hash(challenge.id, code))) return null;
      const value = await accepted(tx, challenge);
      await tx.query("DELETE FROM blot_email_challenges WHERE id = $1", [challenge.id]);
      return { value };
    });
    // Invalid attempts commit before reporting failure, including concurrent guesses.
    if (!result) throw new AuthError("code_expired_or_invalid");
    return result.value;
  }
}
