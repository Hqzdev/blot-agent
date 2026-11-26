import { defineConfig } from 'drizzle-kit';

const url =
  process.env.BLOT_POSTGRES_URL ||
  process.env.POSTGRES_URL ||
  process.env.DATABASE_URL;
if (!url) {
  throw new Error('POSTGRES_URL or DATABASE_URL is required');
}

export default defineConfig({
  schema: './packages/database/src/schema.ts',
  out: './packages/database/migrations',
  dialect: 'postgresql',
  dbCredentials: {
    url,
  },
  strict: true,
  verbose: true,
});
