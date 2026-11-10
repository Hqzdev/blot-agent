import { AuthError } from "../auth/errors.mjs";

export class AccountDeletion {
  #sessions;
  #challenges;
  constructor(sessions, challenges) { this.#sessions = sessions; this.#challenges = challenges; }
  async request(accessToken) {
    const account = await this.#sessions.require(accessToken);
    await this.#challenges.send(account, "delete");
    return null;
  }
  async confirm(accessToken, code) {
    const account = await this.#sessions.require(accessToken);
    return this.#challenges.consume(account.email, "delete", code, async (tx, challenge) => {
      const current = await this.#sessions.require(accessToken, tx);
      if (challenge.owner_id !== current.id) throw new AuthError("session_required", 401);
      // All owner data, sessions, codes, backups and backup parts have cascading foreign keys.
      await tx.query("DELETE FROM blot_accounts WHERE id = $1", [current.id]);
      return null;
    });
  }
}
