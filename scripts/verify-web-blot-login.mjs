import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createServer as createSecureServer } from "node:https";
import { createRequire } from "node:module";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, open, readFile } from "node:fs/promises";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { AccountDatabase } from "../landing/lib/accounts/database.mjs";
import { AccountService } from "../landing/lib/accounts/service.mjs";
import { randomToken } from "../landing/lib/accounts/security.mjs";
import { nativeAttempt } from "../landing/lib/auth/browser-session.mjs";
import { AppHandoff } from "../landing/lib/auth/app-handoff.mjs";
import { WebDatabaseMigrator } from "../apps/web/packages/database/src/web-migrator.mjs";

const require = createRequire(new URL("../landing/package.json", import.meta.url));
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

class PostgresPool {
  database = new PGlite({ extensions: { pgcrypto } });
  tail = Promise.resolve();
  async connect() {
    let release;
    const previous = this.tail;
    this.tail = new Promise(resolve => { release = resolve; });
    await previous;
    return { query: (sql, values) => values?.length ? this.database.query(sql, values)
      : this.database.exec(sql).then(results => results.at(-1)), release };
  }
  async query(sql, values) {
    const client = await this.connect();
    try { return await client.query(sql, values); } finally { client.release(); }
  }
}

class BrowserCookies {
  values = new Map();
  async request(url, options = {}) {
    const headers = new Headers(options.headers);
    headers.set("Cookie", [...this.values].map(([name, value]) => `${name}=${value}`).join("; "));
    const response = await fetch(url, { ...options, headers, redirect: "manual" });
    const destination = response.headers.get('location');
    if (destination) assert.equal(new URL(destination, url).origin, new URL(url).origin, 'Browser navigation stays on the public origin');
    for (const cookie of response.headers.getSetCookie()) {
      const [pair] = cookie.split(";"); const separator = pair.indexOf("=");
      const name = pair.slice(0, separator), value = pair.slice(separator + 1);
      if (value) this.values.set(name, value); else this.values.delete(name);
    }
    return response;
  }
}

const root = fileURLToPath(new URL("../", import.meta.url));
const tlsDirectory = `${root}.build/web-login-tls`;
await mkdir(tlsDirectory, { recursive: true });
const certificate = `${tlsDirectory}/certificate.pem`;
const privateKey = `${tlsDirectory}/private-key.pem`;
if (!process.env.BLOT_LOGIN_TLS_CHILD) {
  const generated = spawnSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", privateKey,
    "-out", certificate, "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], { stdio: "ignore" });
  assert.equal(generated.status, 0, "Generate an isolated localhost TLS certificate");
  const verification = spawn(process.execPath, [fileURLToPath(import.meta.url)], { stdio: "inherit",
    env: { ...process.env, NODE_EXTRA_CA_CERTS: certificate, BLOT_LOGIN_TLS_CHILD: "1" } });
  const [status] = await once(verification, "exit");
  process.exit(status ?? 1);
}
const origin = "https://localhost:3147";
const internalOrigin = "http://127.0.0.1:3148";
const siteOrigin = "http://127.0.0.1:3150";
const proxySecret = randomToken();
process.env.BLOT_WEB_APP_URL = `${origin}/app`;
const pool = new PostgresPool();
const database = new AccountDatabase(pool);
const messages = [];
const accounts = new AccountService({ database, challengeSecret: randomToken(),
  email: { async sendCode(email, code) { messages.push({ email, code }); } } });
let issued, tokenExchanges = 0;
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    if (!path.startsWith("/v1/auth/")) { response.writeHead(404).end(); return; }
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const result = await accounts.request(path.slice("/v1/auth/".length), {
      method: request.method, body: chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {},
      accessToken: request.headers.authorization?.slice(7),
    });
    if (path.endsWith("/browser/token")) { issued = result; tokenExchanges++; }
    response.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(result));
  } catch (error) { response.writeHead(error.status || 500, { "Content-Type": "application/json" }).end(JSON.stringify({ code: error.code || "service_unavailable" })); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const accountOrigin = `http://127.0.0.1:${server.address().port}`;
const tls = { key: await readFile(privateKey), cert: await readFile(certificate) };
const forward = upstream => async (request, response) => {
  try {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const headers = new Headers();
    for (const [name, value] of Object.entries(request.headers)) if (value && name !== 'host') headers.set(name, String(value));
    headers.set('x-forwarded-host', 'internal-upstream.example');
    headers.set('x-forwarded-proto', 'https');
    const result = await fetch(`${upstream}${request.url}`, { method: request.method, headers,
      body: chunks.length ? Buffer.concat(chunks) : undefined, redirect: 'manual' });
    response.writeHead(result.status, { ...Object.fromEntries([...result.headers].filter(([name]) => !['set-cookie','content-encoding','content-length','transfer-encoding'].includes(name))),
      'set-cookie': result.headers.getSetCookie() });
    response.end(Buffer.from(await result.arrayBuffer()));
  } catch { response.writeHead(502).end(); }
};
// Exercise the actual landing proxy, with TLS on both public and upstream hops.
const proxy = createSecureServer(tls, forward(siteOrigin));
const upstream = createSecureServer(tls, forward(internalOrigin));
await new Promise(resolve => upstream.listen(3149, resolve));
await new Promise(resolve => proxy.listen(3147, resolve));
await mkdir(new URL("../.build/", import.meta.url), { recursive: true });
const output = await open(new URL("../.build/web-blot-login-runtime.log", import.meta.url), "w");
const child = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "--hostname", "127.0.0.1", "--port", "3148"], {
  cwd: fileURLToPath(new URL("../apps/web/", import.meta.url)), stdio: ["ignore", output.fd, output.fd],
  env: { ...process.env, NODE_ENV: "production", AUTH_SECRET: randomToken(), AUTH_URL: origin,
    BLOT_AUTH_URL: `${origin}/login`, BLOT_ACCOUNT_SERVICE_URL: accountOrigin, BLOT_WEB_PROXY_SECRET: proxySecret, NEXT_TELEMETRY_DISABLED: "1" },
});
const site = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "--hostname", "127.0.0.1", "--port", "3150"], {
  cwd: fileURLToPath(new URL("../landing/", import.meta.url)), stdio: ["ignore", output.fd, output.fd],
  env: { ...process.env, NODE_ENV: 'production', BLOT_WEB_UPSTREAM_URL: 'https://localhost:3149',
    BLOT_WEB_PROXY_SECRET: proxySecret, NEXT_TELEMETRY_DISABLED: '1' },
});

try {
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (child.exitCode !== null || site.exitCode !== null) throw new Error("Web server exited before readiness");
    try { const response = await fetch(`${origin}/app/api/auth/session`); ready = response.ok; await response.body?.cancel(); } catch {}
    if (ready) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(ready, "Web server ready");
  const email = `${randomUUID()}@example.org`;
  await accounts.request("email/request", { body: { email, name: "Shared Blot Owner", intent: "register" } });
  const owner = await accounts.request("email/verify", { body: { email, code: messages.at(-1).code } });
  const browser = new BrowserCookies();
  const websiteLogin = await browser.request(`${origin}/login`);
  assert.equal(new URL(websiteLogin.headers.get('location')).pathname, '/app/api/auth/blot/start');
  const protectedChat = await browser.request(`${origin}/app/chat`);
  assert.equal(new URL(protectedChat.headers.get('location')).pathname, '/app/login');
  const start = await browser.request(`${origin}/app/api/auth/blot/start?callbackUrl=%2Fchat`);
  assert.equal(start.status, 307);
  const login = new URL(start.headers.get("location"));
  const attempt = nativeAttempt(login.searchParams);
  assert.equal(attempt.clientID, "blot-web");
  const initialCookies = new Map(browser.values);
  assert.ok([...initialCookies.keys()].some(name => name.startsWith('blot_login_attempt_')));
  assert.match(start.headers.getSetCookie().join(';'), /Secure/);
  // Another tab must not overwrite the first attempt's verifier.
  await browser.request(`${origin}/app/api/auth/blot/start`);
  let callback;
  const handoff = new AppHandoff({ prepare: async () => {
    const code = await accounts.request("browser/code", { accessToken: owner.accessToken,
      body: { clientID: attempt.clientID, redirectURI: attempt.redirectURI, codeChallenge: attempt.codeChallenge } });
    const url = new URL(attempt.redirectURI); url.search = new URLSearchParams({ code: code.code, state: attempt.state }).toString();
    return { callbackURL: url.href, expiresAt: code.expiresAt };
  }, navigate: url => { callback = url; } });
  await handoff.open({ query: login.searchParams.toString() });
  const wrongState = new BrowserCookies(); wrongState.values = new Map(initialCookies);
  const invalid = new URL(callback); invalid.searchParams.set("state", "x".repeat(43));
  const rejected = await wrongState.request(invalid);
  assert.equal(new URL(rejected.headers.get("location")).searchParams.get("error"), "blot");
  assert.equal(tokenExchanges, 0);
  const completed = await browser.request(callback);
  assert.equal(new URL(completed.headers.get("location")).pathname, "/app/chat");
  const session = await browser.request(`${origin}/app/api/auth/session`);
  const content = await session.json();
  assert.ok(browser.values.has('__Secure-authjs.session-token'), 'HTTPS uses a Secure session cookie');
  assert.equal(content.user.id, owner.ownerID);
  assert.equal(content.user.email, email);
  assert.ok(!JSON.stringify(content).includes(issued.accessToken));
  assert.equal(tokenExchanges, 1);
  const replay = new BrowserCookies(); replay.values = new Map(initialCookies);
  const replayed = await replay.request(callback);
  assert.equal(new URL(replayed.headers.get("location")).searchParams.get("error"), "blot");
  const legacy = await browser.request(`${origin}/app/api/auth/callback/credentials`, { method: "POST", body: "nickname=legacy&password=unused", headers: { "Content-Type": "application/x-www-form-urlencoded", Origin: origin } });
  assert.ok(legacy.status >= 400 || legacy.headers.get("location"), "Legacy login does not create an identity");
  const staleBrowser = new BrowserCookies(); staleBrowser.values = new Map(browser.values);
  await accounts.request("logout", { accessToken: issued.accessToken });
  const loginAfterRevocation = await staleBrowser.request(`${origin}/app/login`);
  assert.equal(new URL(loginAfterRevocation.headers.get("location"), origin).pathname, "/app/api/auth/blot/start", "A revoked cookie must not loop from login back to chat");
  const revoked = await browser.request(`${origin}/app/api/auth/session`);
  assert.equal(await revoked.json(), null);
  assert.equal((await accounts.request("me", { method: "GET", accessToken: owner.accessToken })).id, owner.ownerID);
  const second = new BrowserCookies();
  const secondStart = await second.request(`${origin}/app/api/auth/blot/start`);
  const secondAttempt = nativeAttempt(new URL(secondStart.headers.get("location")).searchParams);
  const secondCode = await accounts.request("browser/code", { accessToken: owner.accessToken, body: {
    clientID: secondAttempt.clientID, redirectURI: secondAttempt.redirectURI, codeChallenge: secondAttempt.codeChallenge,
  } });
  const secondCallback = new URL(secondAttempt.redirectURI);
  secondCallback.search = new URLSearchParams({ code: secondCode.code, state: secondAttempt.state }).toString();
  await second.request(secondCallback);
  const secondSession = await second.request(`${origin}/app/api/auth/session`);
  assert.equal((await secondSession.json()).user.id, owner.ownerID);
  const csrf = await (await second.request(`${origin}/app/api/auth/csrf`)).json();
  await second.request(`${origin}/app/api/auth/signout`, { method: "POST", headers: { Origin: origin, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ csrfToken: csrf.csrfToken, callbackUrl: `${origin}/app/login?loggedOut=1` }) });
  await assert.rejects(accounts.request("me", { method: "GET", accessToken: issued.accessToken }));
  assert.equal(await (await second.request(`${origin}/app/api/auth/session`)).json(), null);
  const signedOut = await second.request(`${origin}/app/login?loggedOut=1`);
  assert.equal(signedOut.status, 200);
  assert.ok((await signedOut.text()).includes('Вы вышли из Ori'));
  // Apply additive web migrations on the account database and check safe repeat/upgrade.
  const migrator = new WebDatabaseMigrator((sql, values) => pool.query(sql, values));
  assert.equal((await migrator.migrate()).length, 7);
  assert.deepEqual(await migrator.migrate(), []);
  assert.equal((await accounts.request('me', { method: 'GET', accessToken: owner.accessToken })).id, owner.ownerID);
  const legacyID = randomUUID();
  await pool.query("INSERT INTO identity.users(id,email,nickname) VALUES ($1,$2,$3)", [legacyID, email, "legacy-owner"]);
  await pool.query("INSERT INTO identity.blot_profiles(owner_id,nickname) VALUES ($1,$2)", [owner.ownerID, "Blot alias"]);
  assert.equal((await pool.query("SELECT id FROM identity.users WHERE email=$1", [email])).rows[0].id, legacyID);
  assert.equal((await pool.query("SELECT owner_id FROM identity.blot_profiles", [])).rows[0].owner_id, owner.ownerID);
  await pool.query("UPDATE blot_web.migrations SET hash='changed' WHERE tag='0000_clean_foundation'");
  await assert.rejects(migrator.migrate(), /migration has changed/);
  const unknown = new PostgresPool();
  try {
    await unknown.query('CREATE SCHEMA identity; CREATE TABLE identity.users(id text PRIMARY KEY); INSERT INTO identity.users VALUES (\'preserved\')');
    await assert.rejects(new WebDatabaseMigrator((sql, values) => unknown.query(sql, values)).migrate(), /explicit migration baseline/);
    assert.equal((await unknown.query('SELECT id FROM identity.users')).rows[0].id, 'preserved');
    assert.equal((await unknown.query("SELECT to_regclass('blot_web.migrations') AS journal")).rows[0].journal, null);
  } finally { await unknown.database.close(); }
  console.log("Shared Blot login passed: PostgreSQL owner → PKCE → Next.js session; tampering, replay, revocation, logout and legacy-account isolation checked.");
} finally {
  child.kill("SIGTERM");
  site.kill('SIGTERM');
  if (child.exitCode === null) await once(child, "exit");
  if (site.exitCode === null) await once(site, 'exit');
  await new Promise(resolve => server.close(resolve));
  await new Promise(resolve => proxy.close(resolve));
  await new Promise(resolve => upstream.close(resolve));
  await pool.database.close();
  await output.close();
}
