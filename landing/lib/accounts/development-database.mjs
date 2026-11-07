import { mkdirSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { AccountDatabase } from "./database.mjs";

class DevelopmentPostgresPool {
  #postgres;
  #tail = Promise.resolve();
  constructor(directory) { this.#postgres = new PGlite(directory); }
  async connect() {
    let release;
    const previous = this.#tail;
    this.#tail = new Promise(resolve => { release = resolve; });
    await previous;
    return { query: (sql, values) => values?.length ? this.#postgres.query(sql, values)
      : this.#postgres.exec(sql).then(results => results.at(-1)), release };
  }
  async query(sql, values) {
    const client = await this.connect();
    try { return await client.query(sql, values); } finally { client.release(); }
  }
}

export function developmentDatabase() {
  if (process.env.NODE_ENV !== "development" || process.env.BLOT_LOCAL_ACCOUNTS !== "1") throw new Error("Local accounts require development mode");
  // Next compiles routes separately; share one database connection throughout this process.
  mkdirSync(".build", { recursive: true });
  globalThis.__blotDevelopmentDatabase ??= new AccountDatabase(new DevelopmentPostgresPool(".build/accounts"));
  return globalThis.__blotDevelopmentDatabase;
}
