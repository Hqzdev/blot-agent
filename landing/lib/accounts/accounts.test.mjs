import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { AccountDatabase } from "./database.mjs";
import { AccountService } from "./service.mjs";
import { WorkspaceBackups } from "./workspace-backups.mjs";
import { AccountRateLimiter, randomToken, digest } from "./security.mjs";
import { NextRequest } from "next/server.js";
import { YandexAccountIdentity } from "./yandex.mjs";
import { YandexSignIn } from "../auth/yandex-sign-in.mjs";
import { YANDEX_COOKIE, SESSION_COOKIE, unseal } from "../auth/browser-session.mjs";

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

test("Yandex browser login creates a persistent account and completes iPhone/Mac PKCE handoff", async context => {
  process.env.BLOT_WEB_SESSION_SECRET = randomToken();
  const config = { clientID: "blot-yandex", clientSecret: randomToken(), redirectURI: "https://blot.example/auth/yandex/callback" };
  const email = `${randomUUID()}@yandex.ru`, subject = randomUUID();
  let tokenRequests = 0, profileRequests = 0;
  const exchangedCodes = new Set();
  context.mock.method(globalThis, "fetch", async (url, options) => {
    if (url === "https://oauth.yandex.ru/token") {
      tokenRequests++;
      assert.equal(options.body.get("client_secret"), config.clientSecret);
      assert.ok(options.body.get("code_verifier"));
      const code = options.body.get("code");
      if (exchangedCodes.has(code)) return Response.json({ error: "invalid_grant" }, { status: 400 });
      exchangedCodes.add(code);
      return Response.json({ access_token: "private-yandex-token", token_type: "bearer", refresh_token: "never-store-this" });
    }
    assert.equal(url, "https://login.yandex.ru/info?format=json");
    assert.equal(options.headers.Authorization, "OAuth private-yandex-token");
    profileRequests++;
    return Response.json({ id: subject, client_id: config.clientID, default_email: email, real_name: "Yandex Person" });
  });
  const accounts = new AccountService({ database, email: {}, challengeSecret: randomToken(), yandexIdentity: new YandexAccountIdentity(config.clientID) });
  const signIn = new YandexSignIn({ configuration: () => config, accounts: (path, options) => accounts.request(path, options) });
  const owners = [];
  for (const platform of ["ios", "macos"]) {
    const codeVerifier = randomToken(), state = randomToken();
    const query = new URLSearchParams({ response_type: "code", client_id: `blot-${platform}`, redirect_uri: `blot-agent-${platform}:/oauth/account`,
      state, code_challenge: createHash("sha256").update(codeVerifier).digest("base64url"), code_challenge_method: "S256", intent: "login" });
    const started = signIn.start(new NextRequest("https://blot.example/auth/yandex/start?" + query));
    const attemptCookie = started.cookies.get(YANDEX_COOKIE).value;
    const providerState = new URL(started.headers.get("location")).searchParams.get("state");
    const callbackRequest = new NextRequest(`https://blot.example/auth/yandex/callback?state=${providerState}&code=test-code-${platform}`, {
      headers: { cookie: `${YANDEX_COOKIE}=${attemptCookie}` },
    });
    const callback = await signIn.callback(callbackRequest);
    assert.equal(callback.status, 307);
    assert.equal(new URL(callback.headers.get("location")).search, "?" + query.toString());
    assert.equal(callback.cookies.get(YANDEX_COOKIE).value, "");
    const replay = await signIn.callback(callbackRequest);
    assert.equal(new URL(replay.headers.get("location")).searchParams.get("auth_error"), "yandex_failed");
    assert.equal(replay.cookies.has(SESSION_COOKIE), false);
    const tokens = unseal(callback.cookies.get(SESSION_COOKIE).value);
    assert.equal(Object.hasOwn(tokens, "refreshToken"), false);
    assert.equal(Object.hasOwn(tokens, "access_token"), false);
    assert.ok(!callback.headers.get("location").includes("private-yandex-token"));
    const account = await accounts.request("me", { method: "GET", accessToken: tokens.accessToken });
    assert.equal(account.name, "Yandex Person");
    assert.equal(account.email, email);
    owners.push(account.id);
    const { code } = await accounts.request("browser/code", { accessToken: tokens.accessToken, body: {
      clientID: `blot-${platform}`, redirectURI: `blot-agent-${platform}:/oauth/account`, codeChallenge: query.get("code_challenge"),
    } });
    const native = await accounts.request("browser/token", { body: { code, codeVerifier,
      clientID: `blot-${platform}`, redirectURI: `blot-agent-${platform}:/oauth/account` } });
    assert.equal(native.ownerID, account.id);
    await assert.rejects(accounts.request("browser/token", { body: { code, codeVerifier,
      clientID: `blot-${platform}`, redirectURI: `blot-agent-${platform}:/oauth/account` } }), rejectCode("browser_authorization_invalid"));
  }
  assert.equal(owners[0], owners[1]);
  assert.equal(tokenRequests, 4);
  assert.equal(profileRequests, 2);
  const stored = (await database.query("SELECT * FROM blot_accounts WHERE id = $1", [owners[0]])).rows[0];
  assert.equal(stored.yandex_subject, subject);
  assert.equal(stored.google_subject, null);
  assert.equal(stored.password_hash, null);
  assert.equal(stored.verified, true);
});

test("provider sign-in never links matching emails; repeat subjects keep their account", async () => {
  const { email: existingEmail } = await registered();
  for (const provider of ["google", "yandex"]) {
    let identity = { subject: randomUUID(), email: existingEmail, name: "External Person" };
    const accounts = new AccountService({ database, email: {}, challengeSecret: randomToken(),
      [`${provider}Identity`]: { async verify() { return identity; } } });
    const path = `${provider}/login`;
    await assert.rejects(accounts.request(path), rejectCode(`${provider}_link_required`));
    identity = { ...identity, email: `${randomUUID()}@example.org` };
    const tokens = await accounts.request(path);
    const repeated = await Promise.all([accounts.request(path), accounts.request(path)]);
    assert.ok(repeated.every(value => value.ownerID === tokens.ownerID));
    identity = { ...identity, email: `${randomUUID()}@example.org` };
    assert.equal((await accounts.request(path)).ownerID, tokens.ownerID);
  }
});

test("Yandex cancellation and account email collision issue no browser session", async context => {
  process.env.BLOT_WEB_SESSION_SECRET = randomToken();
  const { email } = await registered();
  const config = { clientID: "blot-yandex", clientSecret: randomToken(), redirectURI: "https://blot.example/auth/yandex/callback" };
  context.mock.method(globalThis, "fetch", async url => url === "https://oauth.yandex.ru/token"
    ? Response.json({ access_token: "private-yandex-token", token_type: "bearer" })
    : Response.json({ id: randomUUID(), client_id: config.clientID, default_email: email }));
  const accounts = new AccountService({ database, email: {}, challengeSecret: randomToken(), yandexIdentity: new YandexAccountIdentity(config.clientID) });
  const signIn = new YandexSignIn({ configuration: () => config, accounts: (path, options) => accounts.request(path, options) });
  for (const outcome of ["error=access_denied", "code=code"]) {
    const start = signIn.start(new NextRequest("https://blot.example/auth/yandex/start"));
    const cookie = start.cookies.get(YANDEX_COOKIE).value;
    const state = new URL(start.headers.get("location")).searchParams.get("state");
    const callback = await signIn.callback(new NextRequest(`https://blot.example/auth/yandex/callback?state=${state}&${outcome}`, {
      headers: { cookie: `${YANDEX_COOKIE}=${cookie}` },
    }));
    assert.equal(new URL(callback.headers.get("location")).searchParams.get("auth_error"), outcome.startsWith("error=") ? "yandex_access_denied" : "yandex_link_required");
    assert.equal(callback.cookies.has(SESSION_COOKIE), false);
    assert.equal(callback.cookies.get(YANDEX_COOKIE).value, "");
  }
});

test("Yandex schema upgrade is repeatable and preserves existing accounts and sessions", async () => {
  const legacyPool = new TestPostgresPool(), legacy = new AccountDatabase(legacyPool);
  try {
    await legacy.initialize();
    const original = new AccountService({ database: legacy, challengeSecret: randomToken(), email: {},
      googleIdentity: { async verify() { return { subject: "existing-google", email: "existing@example.org", name: "Existing Person" }; } } });
    const tokens = await original.request("google/login");
    // Recreate the pre-Yandex schema with an existing Google account and active session.
    await legacy.query("ALTER TABLE blot_accounts DROP COLUMN yandex_subject");
    await new AccountDatabase(legacyPool).initialize();
    await new AccountDatabase(legacyPool).initialize();
    const profile = await original.request("me", { method: "GET", accessToken: tokens.accessToken });
    assert.equal(profile.email, "existing@example.org");
    const stored = (await legacy.query("SELECT google_subject, yandex_subject FROM blot_accounts WHERE id = $1", [profile.id])).rows[0];
    assert.deepEqual(stored, { google_subject: "existing-google", yandex_subject: null });
    await legacy.query("UPDATE blot_accounts SET yandex_subject = $1 WHERE id = $2", ["unique-yandex", profile.id]);
    await assert.rejects(legacy.query(`INSERT INTO blot_accounts(id, workspace_id, email, name, yandex_subject)
      VALUES ($1, $2, $3, $4, $5)`, [randomUUID(), randomUUID(), "other@example.org", "Other", "unique-yandex"]), error => error.code === "23505");
  } finally { await legacyPool.close(); }
});
