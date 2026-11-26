import 'dotenv/config';
import postgres from 'postgres';
import { databaseTLS } from './tls.mjs';
import { WebDatabaseMigrator } from './web-migrator.mjs';

const url =
  process.env.BLOT_POSTGRES_URL ||
  process.env.POSTGRES_URL ||
  process.env.DATABASE_URL;
if (!url) throw new Error('POSTGRES_URL or DATABASE_URL is required');
const client = postgres(url, {
  ...databaseTLS(url),
  max: 1,
  prepare: false,
  connect_timeout: 15,
});
const connection = await client.reserve();
try {
  const migrated = await new WebDatabaseMigrator(async (sql, values = []) => ({
    rows: await connection.unsafe(sql, values),
  })).migrate();
  console.log(
    'Blot web database ready; applied migrations:',
    migrated.length ? migrated.join(', ') : 'none',
  );
} finally {
  connection.release();
  await client.end();
}
