import { test } from "node:test";
import assert from "node:assert/strict";
import { AccountDatabase } from "./database.mjs";
import { accountDatabaseURL } from "./database-url.mjs";
import { accountConnectionOptions } from "./connection-options.mjs";
import { Client } from "pg";
import { createSecureContext } from "node:tls";

test("Supabase TLS trusts its CA and URL parameters cannot disable verification", () => {
  const options = accountConnectionOptions("postgresql://user:password@aws-0-eu-west-1.pooler.supabase.com:6543/postgres?sslmode=no-verify&sslrootcert=untrusted");
  const client = new Client(options);
  assert.equal(client.connectionParameters.ssl.rejectUnauthorized, true);
  assert.match(client.connectionParameters.ssl.ca, /BEGIN CERTIFICATE/);
  assert.doesNotThrow(() => createSecureContext(options.ssl));
  const foreign = "postgresql://user:password@supabase.com.attacker.example/postgres";
  assert.deepEqual(accountConnectionOptions(foreign), { connectionString: foreign });
});

test("the selected server database overrides legacy Neon without using public credentials", () => {
  assert.equal(accountDatabaseURL({ BLOT_POSTGRES_URL: "new", DATABASE_URL: "old" }), "new");
  assert.equal(accountDatabaseURL({ DATABASE_URL: "legacy" }), "legacy");
  assert.equal(accountDatabaseURL({ NEXT_PUBLIC_POSTGRES_URL: "public" }), undefined);
});

test("database initialization reports a safe failure, shares in-flight work and retries", async t => {
  const log = t.mock.method(console, "error", () => {});
  let connects = 0;
  const database = new AccountDatabase({
    async connect() {
      connects++;
      if (connects === 1) throw Object.assign(new Error("postgresql://private-password@host/account"), {
        code: "ECONNREFUSED", detail: "private account data",
      });
      return { async query() {}, release() {} };
    },
  });
  const first = await Promise.allSettled([database.initialize(), database.initialize()]);
  assert.equal(connects, 1);
  for (const result of first) {
    assert.equal(result.status, "rejected");
    assert.equal(result.reason.code, "auth_service_unavailable");
    assert.equal(result.reason.status, 503);
  }
  assert.deepEqual(log.mock.calls.map(call => call.arguments), [
    [JSON.stringify({ event: "account_database_initialization_failed", code: "ECONNREFUSED" })],
  ]);
  await database.initialize();
  await database.initialize();
  assert.equal(connects, 2);
});

test("database diagnostics discard arbitrary driver error codes", async t => {
  const log = t.mock.method(console, "error", () => {});
  const database = new AccountDatabase({ async connect() { throw { code: "private\naccount@example.org" }; } });
  await assert.rejects(database.initialize(), error => error.code === "auth_service_unavailable");
  assert.equal(JSON.parse(log.mock.calls[0].arguments[0]).code, "UNKNOWN");
});
