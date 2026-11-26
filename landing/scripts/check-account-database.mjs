import { Pool } from "pg";
import { accountDatabaseURL } from "../lib/accounts/database-url.mjs";
import { accountConnectionOptions } from "../lib/accounts/connection-options.mjs";

// Read-only deployment check: never print connection strings, rows or SQL errors.
const connectionString = accountDatabaseURL();
if (!connectionString) throw new Error("Account database is not configured");
const pool = new Pool({ ...accountConnectionOptions(connectionString), max: 1, connectionTimeoutMillis: 10_000 });
let client;
let stage = "connect";
try {
  client = await pool.connect();
  await client.query("BEGIN READ ONLY");
  stage = "schema";
  const { rows } = await client.query(`SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name IN ('blot_accounts', 'blot_sessions', 'blot_browser_codes')`);
  const required = {
    blot_accounts: ["id", "workspace_id", "email", "name", "google_subject", "yandex_subject", "verified", "avatar_url"],
    blot_sessions: ["id", "owner_id", "access_hash", "refresh_hash", "access_expires", "refresh_expires", "revoked"],
    blot_browser_codes: ["code_hash", "session_id", "owner_id", "client_id", "redirect_uri", "challenge", "expires_at"],
  };
  for (const [table, columns] of Object.entries(required)) {
    const actual = new Set(rows.filter(row => row.table_name === table).map(row => row.column_name));
    if (columns.some(column => !actual.has(column))) throw Object.assign(new Error(), { code: "SCHEMA_INCOMPLETE" });
  }
  const security = await client.query(`SELECT relrowsecurity FROM pg_class
    WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
    AND relname IN ('blot_accounts','blot_sessions','blot_email_challenges','blot_auth_rates',
      'blot_browser_codes','blot_workspace_backups','blot_workspace_backup_parts')`);
  if (security.rows.length !== 7 || security.rows.some(row => !row.relrowsecurity)) {
    throw Object.assign(new Error(), { code: "ACCOUNT_RLS_REQUIRED" });
  }
  await client.query("ROLLBACK");
  console.log("Account database: read-only connection and account schema verified");
} catch (error) {
  const code = typeof error?.code === "string" && /^[A-Z0-9_]{1,64}$/.test(error.code) ? error.code : "UNKNOWN";
  const message = typeof error?.message === "string" ? error.message : "";
  const reason = /compute.*quota|quota.*compute/i.test(message) ? "compute_quota"
    : /storage.*quota|quota.*storage/i.test(message) ? "storage_quota"
    : /quota/i.test(message) ? "quota" : /too many connections/i.test(message) ? "connection_limit" : "unknown";
  console.error(JSON.stringify({ event: "account_database_check_failed", stage, code, reason }));
  process.exitCode = 1;
} finally {
  client?.release();
  await pool.end();
}
