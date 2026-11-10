import { randomUUID } from "node:crypto";
import { AuthError } from "../auth/errors.mjs";
import { emailAddress } from "./security.mjs";

export class EmailSignIn {
  #database;
  #challenges;
  #sessions;
  constructor(database, challenges, sessions) {
    this.#database = database; this.#challenges = challenges; this.#sessions = sessions;
  }

  async request({ email: address, name, intent }) {
    const email = emailAddress(typeof address === "string" ? address.trim() : address);
    if (!["login", "register"].includes(intent)) throw new AuthError("invalid_request");
    if (intent === "register" && (typeof name !== "string" || !name.trim() || name.length > 200)) throw new AuthError("invalid_name");
    let account = (await this.#database.query("SELECT * FROM blot_accounts WHERE email = $1", [email])).rows[0];
    if (intent === "register") {
      account = (await this.#database.query(`INSERT INTO blot_accounts(id, workspace_id, email, name)
        VALUES ($1, $2, $3, $4) ON CONFLICT(email) DO UPDATE SET email = EXCLUDED.email RETURNING *`,
      [randomUUID(), randomUUID(), email, name.trim()])).rows[0];
    }
    if (account && (account.verified || intent === "register")) {
      await this.#challenges.send(account, "signin", { name: intent === "register" ? name.trim() : null });
    }
    return null;
  }

  async verify({ email, code }) {
    return this.#challenges.consume(emailAddress(typeof email === "string" ? email.trim() : email), "signin", code, async (tx, challenge) => {
      if (!challenge.verified) {
        if (!challenge.registration_name) throw new AuthError("code_expired_or_invalid");
        await tx.query("UPDATE blot_accounts SET name = $1, verified = true WHERE id = $2",
          [challenge.registration_name, challenge.owner_id]);
      }
      return this.#sessions.create(tx, { id: challenge.owner_id, workspace_id: challenge.workspace_id });
    });
  }
}
