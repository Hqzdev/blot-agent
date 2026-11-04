package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.CloudDatabase;
import java.time.*;

public final class CloudRateLimiter {
  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final Clock clock;

  public CloudRateLimiter(CloudDatabase database, CloudTokens tokens, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.clock = clock;
  }

  public void check(String key, int limit, Duration window) {
    long now = clock.millis();
    String digest = tokens.digest(key);
    boolean allowed =
        database.transact(
            tx -> {
              var old =
                  tx.one(
                      "SELECT count, expires FROM auth_rates WHERE key = ?",
                      r -> new long[] {r.getLong(1), r.getLong(2)},
                      digest);
              long count = old.filter(v -> v[1] > now).map(v -> v[0]).orElse(0L);
              long expires =
                  old.filter(v -> v[1] > now).map(v -> v[1]).orElse(now + window.toMillis());
              tx.execute(
                  "INSERT INTO auth_rates(key, count, expires) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET count = excluded.count, expires = excluded.expires",
                  digest,
                  Math.min(count + 1, limit + 1L),
                  expires);
              tx.execute("DELETE FROM auth_rates WHERE expires < ?", now - window.toMillis());
              return count < limit;
            });
    if (!allowed) throw new CloudFailure(429, "rate_limited");
  }
}
