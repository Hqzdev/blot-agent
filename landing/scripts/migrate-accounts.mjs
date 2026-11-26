import { Pool } from "pg";
import { AccountDatabase } from "../lib/accounts/database.mjs";
import { accountDatabaseURL } from "../lib/accounts/database-url.mjs";
import { accountConnectionOptions } from "../lib/accounts/connection-options.mjs";

const connectionString = accountDatabaseURL();
if (!connectionString) throw new Error("Account database is not configured");
const pool = new Pool({ ...accountConnectionOptions(connectionString), max: 1, connectionTimeoutMillis: 10_000 });
try {
  await new AccountDatabase(pool).initialize();
  console.log("Blot account database migrations applied");
} catch {
  process.exitCode = 1;
} finally {
  await pool.end();
}
