import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AccountService } from "../lib/accounts/service.mjs";
import { accountDatabaseURL } from "../lib/accounts/database-url.mjs";
import { accountConnectionOptions } from "../lib/accounts/connection-options.mjs";
import { randomToken } from "../lib/accounts/security.mjs";

// Exercise the account/session/PKCE path with a synthetic verified identity.
// One real PostgreSQL transaction rolls back every test account and token.
const pool = new Pool({ ...accountConnectionOptions(accountDatabaseURL()), max: 1, connectionTimeoutMillis: 10_000 });
let client;
try {
  client = await pool.connect();
  await client.query("BEGIN");
  const database = { async initialize() {}, query: (...args) => client.query(...args), transaction: operation => operation(client) };
  const subject = randomUUID();
  const service = new AccountService({ database, challengeSecret: randomToken(),
    email: { async sendCode() { throw new Error("Email is not allowed during this check"); } },
    googleIdentity: { async verify() { return { subject, email: `${subject}@example.invalid`, name: "Deployment verification" }; } } });
  const tokens = await service.request("google/login", { body: { idToken: "synthetic", nonce: randomToken() } });
  assert.equal((await service.request("me", { method: "GET", accessToken: tokens.accessToken })).id, tokens.ownerID);
  for (const platform of ["macos", "ios"]) {
    const codeVerifier = randomToken();
    const native = { clientID: `blot-${platform}`, redirectURI: `blot-agent-${platform}:/oauth/account` };
    const { code } = await service.request("browser/code", { accessToken: tokens.accessToken,
      body: { ...native, codeChallenge: createHash("sha256").update(codeVerifier).digest("base64url") } });
    const session = await service.request("browser/token", { body: { ...native, code, codeVerifier } });
    assert.equal(session.ownerID, tokens.ownerID);
    await assert.rejects(service.request("browser/token", { body: { ...native, code, codeVerifier } }),
      error => error.code === "browser_authorization_invalid");
  }
  console.log("Account sessions and Mac/iPhone PKCE handoff verified; test data rolled back");
} catch (error) {
  const code = typeof error?.code === "string" && /^[A-Za-z0-9_]{1,64}$/.test(error.code) ? error.code : "verification_failed";
  console.error(JSON.stringify({ event: "account_handoff_check_failed", code }));
  process.exitCode = 1;
} finally {
  if (client) {
    try { await client.query("ROLLBACK"); } finally { client.release(); }
  }
  await pool.end();
}
