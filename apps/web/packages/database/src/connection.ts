import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { databaseTLS } from './tls.mjs';

import * as schema from './schema';

export class DatabaseConnection {
  readonly client;
  readonly db;

  constructor(url: string) {
    this.client = postgres(url, {
      ...databaseTLS(url),
      connect_timeout: 10,
      idle_timeout: 20,
      max: 10,
      max_lifetime: 60 * 30,
      prepare: false,
      transform: {
        undefined: null,
      },
    });
    this.db = drizzle(this.client, { schema });
  }

  async close(): Promise<void> {
    await this.client.end();
  }
}

interface DatabaseGlobal {
  connection?: DatabaseConnection;
}

const databaseGlobal = globalThis as typeof globalThis & DatabaseGlobal;

export class DatabaseConnectionProvider {
  get(): DatabaseConnection {
    const url =
      process.env.BLOT_POSTGRES_URL ||
      process.env.POSTGRES_URL ||
      process.env.DATABASE_URL;
    if (!url) {
      throw new Error('POSTGRES_URL or DATABASE_URL is required');
    }

    if (!databaseGlobal.connection) {
      databaseGlobal.connection = new DatabaseConnection(url);
    }

    return databaseGlobal.connection;
  }
}
