export interface RateLimitState {
  count: number;
  ttlSeconds: number;
}

export interface RateLimitStore {
  increment(key: string, windowSeconds: number): Promise<RateLimitState>;
}

export interface RateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: Date;
}

interface InMemoryEntry {
  count: number;
  expiresAt: number;
}

export class InMemoryRateLimitStore implements RateLimitStore {
  private readonly entries = new Map<string, InMemoryEntry>();

  async increment(key: string, windowSeconds: number): Promise<RateLimitState> {
    const now = Date.now();
    const existing = this.entries.get(key);
    const entry =
      existing && existing.expiresAt > now
        ? existing
        : {
            count: 0,
            expiresAt: now + windowSeconds * 1000,
          };
    entry.count += 1;
    this.entries.set(key, entry);
    return {
      count: entry.count,
      ttlSeconds: Math.max(1, Math.ceil((entry.expiresAt - now) / 1000)),
    };
  }
}

export class UpstashRateLimitStore implements RateLimitStore {
  constructor(
    private readonly url: string,
    private readonly token: string,
  ) {}

  async increment(key: string, windowSeconds: number): Promise<RateLimitState> {
    const script =
      "local count=redis.call('INCR',KEYS[1]);if count==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end;return {count,redis.call('TTL',KEYS[1])}";
    const response = await fetch(this.url, {
      body: JSON.stringify([
        'EVAL',
        script,
        '1',
        key,
        windowSeconds.toString(),
      ]),
      headers: {
        authorization: `Bearer ${this.token}`,
        'content-type': 'application/json',
      },
      method: 'POST',
    });

    if (!response.ok) {
      throw new Error(`Redis rate limit failed with ${response.status}`);
    }

    const payload = (await response.json()) as {
      result?: [number, number];
    };
    if (!payload.result) {
      throw new Error('Redis rate limit returned an invalid response');
    }

    return {
      count: Number(payload.result[0]),
      ttlSeconds: Math.max(1, Number(payload.result[1])),
    };
  }
}

export class RateLimiter {
  constructor(
    private readonly store: RateLimitStore,
    private readonly limit: number,
    private readonly windowSeconds: number,
    private readonly namespace: string,
  ) {}

  async consume(identity: string): Promise<RateLimitDecision> {
    const state = await this.store.increment(
      `${this.namespace}:${identity}`,
      this.windowSeconds,
    );
    return {
      allowed: state.count <= this.limit,
      limit: this.limit,
      remaining: Math.max(0, this.limit - state.count),
      resetAt: new Date(Date.now() + state.ttlSeconds * 1000),
    };
  }
}

export class RateLimitStoreFactory {
  create(environment: NodeJS.ProcessEnv): RateLimitStore {
    const url = environment.UPSTASH_REDIS_REST_URL;
    const token = environment.UPSTASH_REDIS_REST_TOKEN;

    if (url && token) {
      return new UpstashRateLimitStore(url, token);
    }

    if (environment.NODE_ENV === 'production') {
      throw new Error('Production rate limiting requires Upstash Redis');
    }

    return new InMemoryRateLimitStore();
  }
}
