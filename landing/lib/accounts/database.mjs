import { Pool } from "pg";
import { attachDatabasePool } from "@vercel/functions";
import { readFile } from "node:fs/promises";
import { AuthError } from "../auth/errors.mjs";
import { accountDatabaseURL } from "./database-url.mjs";
import { accountConnectionOptions } from "./connection-options.mjs";

export class AccountDatabase {
  #pool;
  #ready;

  constructor(pool) { this.#pool = pool; }

  async initialize() {
    this.#ready ??= this.#migrate().catch(error => {
      this.#ready = undefined;
      // Driver messages/details can contain credentials or account data.
      const code = typeof error?.code === "string" && /^[A-Z0-9_]{1,64}$/.test(error.code) ? error.code : "UNKNOWN";
      console.error(JSON.stringify({ event: "account_database_initialization_failed", code }));
      throw new AuthError("auth_service_unavailable", 503);
    });
    await this.#ready;
  }

  async #migrate() {
    const schema = await readFile(new URL("./schema.sql", import.meta.url), "utf8");
    await this.transaction(async tx => {
      await tx.query("SELECT pg_advisory_xact_lock(170112, 1)");
      await tx.query(schema);
    });
  }

  async query(sql, parameters = []) { return this.#pool.query(sql, parameters); }

  async transaction(operation) {
    const client = await this.#pool.connect();
    try {
      await client.query("BEGIN");
      const result = await operation(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally { client.release(); }
  }
}

let database;
export function accountDatabase() {
  if (!database) {
    const connectionString = accountDatabaseURL();
    if (!connectionString) throw new AuthError("auth_service_unconfigured", 503);
    const pool = new Pool({ ...accountConnectionOptions(connectionString), max: 4, idleTimeoutMillis: 5000, connectionTimeoutMillis: 10_000 });
    attachDatabasePool(pool);
    database = new AccountDatabase(pool);
  }
  return database;
}
