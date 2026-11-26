import { DatabaseConnectionProvider } from '@teya/database';
import { type RateLimitStore, RateLimitStoreFactory } from '@teya/platform';

type Query = (
  sql: string,
  values: (string | number)[],
) => Promise<{ count: number; ttl_seconds: number }[]>;

export class PostgresRateLimitStore implements RateLimitStore {
  constructor(
    private readonly query: Query = async (sql, values) => {
      const rows = await new DatabaseConnectionProvider()
        .get()
        .client.unsafe(sql, values);
      return rows as unknown as { count: number; ttl_seconds: number }[];
    },
  ) {}

  async increment(key: string, windowSeconds: number) {
    const [state] = await this.query(
      `
      INSERT INTO blot_web.rate_limits AS limits (key, count, resets_at)
      VALUES ($1, 1, now() + make_interval(secs => $2))
      ON CONFLICT (key) DO UPDATE SET
        count = CASE WHEN limits.resets_at > now() THEN limits.count + 1 ELSE 1 END,
        resets_at = CASE WHEN limits.resets_at > now() THEN limits.resets_at ELSE EXCLUDED.resets_at END
      RETURNING count, greatest(1, ceil(extract(epoch FROM resets_at - now())))::integer AS ttl_seconds
    `,
      [key, windowSeconds],
    );
    if (!state) throw new Error('PostgreSQL rate limit unavailable');
    return {
      count: Number(state.count),
      ttlSeconds: Number(state.ttl_seconds),
    };
  }
}

export function createWebRateLimitStore(): RateLimitStore {
  if (
    process.env.UPSTASH_REDIS_REST_URL &&
    process.env.UPSTASH_REDIS_REST_TOKEN
  )
    return new RateLimitStoreFactory().create(process.env);
  if (
    process.env.BLOT_POSTGRES_URL ||
    process.env.POSTGRES_URL ||
    process.env.DATABASE_URL
  )
    return new PostgresRateLimitStore();
  return new RateLimitStoreFactory().create(process.env);
}
