import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
import { PostgresRateLimitStore } from '../../lib/services/web-rate-limit-store';

const require = createRequire(
  new URL('../../../../landing/package.json', import.meta.url),
);
const { PGlite } = require('@electric-sql/pglite');

test('PostgreSQL rate limits are atomic across instances and reset expired windows', async () => {
  const database = new PGlite();
  try {
    await database.exec(
      'CREATE SCHEMA blot_web; CREATE TABLE blot_web.rate_limits(key varchar(256) PRIMARY KEY, count integer NOT NULL, resets_at timestamptz NOT NULL)',
    );
    const query = async (sql: string, values: (string | number)[]) =>
      (await database.query(sql, values)).rows;
    const first = new PostgresRateLimitStore(query);
    const second = new PostgresRateLimitStore(query);
    const results = await Promise.all(
      Array.from({ length: 20 }, (_, index) =>
        (index % 2 ? first : second).increment('chat:owner', 60),
      ),
    );
    assert.deepEqual(
      results.map((result) => result.count).sort((a, b) => a - b),
      Array.from({ length: 20 }, (_, index) => index + 1),
    );
    assert.equal((await second.increment('chat:other-owner', 60)).count, 1);
    await database.exec(
      "UPDATE blot_web.rate_limits SET resets_at=now()-interval '1 second' WHERE key='chat:owner'",
    );
    assert.equal((await first.increment('chat:owner', 60)).count, 1);
    assert.ok(
      results.every(
        (result) => result.ttlSeconds > 0 && result.ttlSeconds <= 60,
      ),
    );
  } finally {
    await database.close();
  }
});
