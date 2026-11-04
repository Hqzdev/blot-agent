import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { AccountDatabase } from "./database.mjs";
import { AccountService } from "./service.mjs";
import { WorkspaceBackups } from "./workspace-backups.mjs";
import { AccountRateLimiter, randomToken, digest } from "./security.mjs";

// PGlite runs PostgreSQL itself. The adapter only supplies pg's pool/transaction interface.
class TestPostgresPool {
  #postgres = new PGlite();
  #tail = Promise.resolve();
  async connect() {
    let release;
    const previous = this.#tail;
    this.#tail = new Promise(resolve => { release = resolve; });
    await previous;
    return { query: (sql, values) => values?.length
      ? this.#postgres.query(sql, values) : this.#postgres.exec(sql).then(results => results.at(-1)), release };
  }
  async query(sql, values) {
    const client = await this.connect();
    try { return await client.query(sql, values); } finally { client.release(); }
  }
  async close() { await this.#postgres.close(); }
}

const pool = new TestPostgresPool();
const database = new AccountDatabase(pool);
const messages = [];
const service = new AccountService({ database, challengeSecret: randomToken(),
  email: { async sendCode(email, code, purpose) { messages.push({ email, code, purpose }); } },
  googleIdentity: { async verify() { throw new Error("Google verification is exercised separately"); } } });
const password = "a long private password";
const rejectCode = code => error => error.code === code;
async function registered() {
  const email = `${randomUUID()}@example.org`;
  await service.request("register", { body: { email, password, name: "Postgres test" } });
  const code = messages.findLast(m => m.email === email).code;
  const tokens = await service.request("verify", { body: { email, code } });
  return { email, tokens, code };
}
before(async () => { await database.initialize(); });
after(async () => { await pool.close(); });

test("registration verifies email once; hashes, refresh rotation and logout persist", async () => {
  const { email, tokens, code } = await registered();
  const stored = (await database.query("SELECT * FROM blot_accounts WHERE email = $1", [email])).rows[0];
  assert.match(stored.password_hash, /^scrypt\$/);
  assert.ok(!stored.password_hash.includes(password));
  const profile = await service.request("me", { method: "GET", accessToken: tokens.accessToken });
  assert.equal(profile.email, email);
  await assert.rejects(service.request("verify", { body: { email, code } }), rejectCode("code_expired_or_invalid"));
  const refreshed = await service.request("refresh", { body: { refreshToken: tokens.refreshToken } });
  assert.equal(refreshed.sessionID, tokens.sessionID);
  assert.notEqual(refreshed.refreshToken, tokens.refreshToken);
  await assert.rejects(service.request("refresh", { body: { refreshToken: tokens.refreshToken } }), rejectCode("session_expired"));
  await assert.rejects(service.request("me", { method: "GET", accessToken: tokens.accessToken }), rejectCode("session_expired"));
  await service.request("logout", { accessToken: refreshed.accessToken });
  await assert.rejects(service.request("me", { method: "GET", accessToken: refreshed.accessToken }), rejectCode("session_expired"));
});

test("five failed email guesses remain spent after transaction commit", async () => {
  const email = `${randomUUID()}@example.org`;
  await service.request("register", { body: { email, password, name: "Attempts" } });
  const code = messages.findLast(m => m.email === email).code;
  const wrong = code === "000000" ? "111111" : "000000";
  for (let i = 0; i < 5; i++) await assert.rejects(service.request("verify", { body: { email, code: wrong } }), rejectCode("code_expired_or_invalid"));
  await assert.rejects(service.request("verify", { body: { email, code } }), rejectCode("code_expired_or_invalid"));
  assert.equal((await database.query("SELECT attempts FROM blot_email_challenges c JOIN blot_accounts a ON a.id = c.owner_id WHERE a.email = $1", [email])).rows[0].attempts, 5);
});

test("re-registration cannot replace an existing verified password", async () => {
  const { email, tokens } = await registered();
  await database.query("DELETE FROM blot_auth_rates");
  await service.request("register", { body: { email, password: "different malicious password", name: "Replaced" } });
  const code = messages.findLast(m => m.email === email).code;
  await service.request("verify", { body: { email, code } });
  await service.request("login", { body: { email, password } });
  await assert.rejects(service.request("login", { body: { email, password: "different malicious password" } }), rejectCode("wrong_credentials"));
  assert.equal((await service.request("me", { method: "GET", accessToken: tokens.accessToken })).name, "Postgres test");
});

test("password reset revokes all sessions and never reveals an unknown email", async () => {
  const { email, tokens } = await registered();
  await service.request("password/request", { body: { email } });
  await assert.rejects(service.request("password/request", { body: { email } }), rejectCode("challenge_cooldown"));
  const code = messages.findLast(m => m.email === email && m.purpose === "reset").code;
  await service.request("password/reset", { body: { email, code, password: "new private password" } });
  await assert.rejects(service.request("refresh", { body: { refreshToken: tokens.refreshToken } }), rejectCode("session_expired"));
  await assert.rejects(service.request("login", { body: { email, password } }), rejectCode("wrong_credentials"));
  await service.request("login", { body: { email, password: "new private password" } });
  assert.equal(await service.request("password/request", { body: { email: "unknown@example.org" } }), null);
  await assert.rejects(service.request("password/request", { body: { email: "unknown@example.org" } }), rejectCode("challenge_cooldown"));
});

test("native handoff rejects wrong PKCE, wrong client and concurrent code replay", async () => {
  const { tokens } = await registered();
  const codeVerifier = randomToken(), codeChallenge = createHash("sha256").update(codeVerifier).digest("base64url");
  const client = { clientID: "blot-ios", redirectURI: "blot-agent-ios:/oauth/account" };
  const { code } = await service.request("browser/code", { accessToken: tokens.accessToken, body: { ...client, codeChallenge } });
  await assert.rejects(service.request("browser/token", { body: { ...client, code, codeVerifier: randomToken() } }), rejectCode("browser_authorization_invalid"));
  await assert.rejects(service.request("browser/token", { body: { ...client, redirectURI: "https://attacker.org", code, codeVerifier } }), rejectCode("browser_authorization_invalid"));
  const exchanges = await Promise.allSettled([1, 2].map(() => service.request("browser/token", { body: { ...client, code, codeVerifier } })));
  assert.equal(exchanges.filter(r => r.status === "fulfilled").length, 1);
  const native = exchanges.find(r => r.status === "fulfilled").value;
  assert.equal(native.ownerID, tokens.ownerID);
  assert.notEqual(native.sessionID, tokens.sessionID);
  await service.request("logout", { accessToken: tokens.accessToken });
  await service.request("me", { method: "GET", accessToken: native.accessToken });
});

test("Postgres rate limits share state across service instances", async () => {
  const a = new AccountRateLimiter(database), b = new AccountRateLimiter(database);
  const key = randomToken();
  await a.check(key, 1, 900);
  await assert.rejects(b.check(key, 1, 900), rejectCode("rate_limited"));
});

test("workspace backup commits complete data atomically and isolates accounts", async () => {
  const owner = await registered(), outsider = await registered();
  const account = await service.authenticate(owner.tokens.accessToken), other = await service.authenticate(outsider.tokens.accessToken);
  const backups = new WorkspaceBackups(database);
  const snapshotID = randomUUID();
  const bytes = Buffer.from(JSON.stringify({ id: snapshotID, workspaceID: owner.tokens.workspaceID, ownerID: owner.tokens.ownerID,
    watermark: {}, relayCursor: 0, records: [{ kind: "Conversation", content: "A private chat" }, { kind: "Project", name: "A project" }] }));
  const input = { snapshotID, deviceID: randomUUID(), digest: digest(bytes), byteCount: bytes.length, chunkCount: 1 };
  await backups.begin(account, input);
  await assert.rejects(backups.commit(account, snapshotID), rejectCode("invalid_workspace_backup"));
  assert.deepEqual(await backups.list(account), []);
  await backups.putPart(account, snapshotID, 0, { data: bytes.toString("base64") });
  await backups.commit(account, snapshotID);
  assert.equal((await backups.list(account))[0].snapshotID, snapshotID);
  assert.deepEqual(await backups.list(other), []);
  await assert.rejects(backups.part(other, snapshotID, 0), rejectCode("not_found"));
  assert.equal(Buffer.from((await backups.part(account, snapshotID, 0)).data, "base64").toString(), bytes.toString());
  // Retrying after a lost commit response is safe, but committed bytes remain immutable.
  await backups.putPart(account, snapshotID, 0, { data: bytes.toString("base64") });
  await backups.commit(account, snapshotID);
  const altered = Buffer.from(bytes); altered[0] ^= 1;
  await assert.rejects(backups.putPart(account, snapshotID, 0, { data: altered.toString("base64") }), rejectCode("invalid_workspace_backup"));
});
