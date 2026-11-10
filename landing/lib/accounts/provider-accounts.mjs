import { randomUUID } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";

const SUBJECT_COLUMNS = { google: "google_subject", yandex: "yandex_subject" };

export class ProviderAccounts {
  #database;
  #identity;
  #sessions;
  #provider;
  #column;
  constructor(database, identity, sessions, provider) {
    if (!Object.hasOwn(SUBJECT_COLUMNS, provider)) throw new TypeError("Unsupported account provider");
    this.#database = database; this.#identity = identity; this.#sessions = sessions;
    this.#provider = provider; this.#column = SUBJECT_COLUMNS[provider];
  }

  async login(...credentials) {
    const identity = await this.#identity.verify(...credentials);
    return this.#database.transaction(async tx => {
      await tx.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`${this.#provider}:${identity.subject}`]);
      await tx.query("SELECT pg_advisory_xact_lock(hashtext($1))", [identity.email]);
      let account = (await tx.query(`SELECT * FROM blot_accounts WHERE ${this.#column} = $1 AND verified`, [identity.subject])).rows[0];
      if (!account) {
        if ((await tx.query("SELECT id FROM blot_accounts WHERE email = $1", [identity.email])).rows[0]) throw new AuthError(`${this.#provider}_link_required`, 409);
        account = (await tx.query(`INSERT INTO blot_accounts(id, workspace_id, email, name, ${this.#column}, verified)
          VALUES ($1, $2, $3, $4, $5, true) RETURNING *`,
        [randomUUID(), randomUUID(), identity.email, identity.name, identity.subject])).rows[0];
      }
      await tx.query("UPDATE blot_accounts SET avatar_url = $1 WHERE id = $2", [identity.avatarURL ?? null, account.id]);
      return this.#sessions.create(tx, account);
    });
  }
}
