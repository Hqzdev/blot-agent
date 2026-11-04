package dev.blot.cloud.model;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.CloudDatabase;
import java.time.*;
import java.util.*;

/** Counts only usage metadata. An ambiguous generation retains its reservation. */
public final class CloudModelQuota {
  public record Usage(long limit, long used, long remaining) {}

  private final CloudDatabase database;
  private final Clock clock;
  private final long limit;

  public CloudModelQuota(CloudDatabase database, Clock clock, long limit) {
    if (limit < 1 || limit > 100_000_000) throw new IllegalArgumentException("Invalid daily quota");
    this.database = database;
    this.clock = clock;
    this.limit = limit;
  }

  public void reserve(CloudActor actor, UUID requestID, long amount) {
    if (requestID == null || amount < 1) throw new CloudFailure(400, "invalid_generation");
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          if (tx.one(
                  "SELECT request_id FROM model_usage WHERE request_id = ?",
                  r -> r.getString(1),
                  requestID)
              .isPresent()) throw new CloudFailure(409, "generation_already_started");
          long used =
              tx.one(
                      "SELECT COALESCE(SUM(COALESCE(actual, reserved)), 0) FROM model_usage WHERE owner_id = ? AND created_at >= ?",
                      r -> r.getLong(1),
                      actor.ownerID(),
                      day())
                  .orElse(0L);
          if (used > limit - amount) throw new CloudFailure(429, "model_quota_exceeded");
          tx.execute(
              "INSERT INTO model_usage(owner_id, request_id, reserved, state, created_at) VALUES (?, ?, ?, 'RESERVED', ?)",
              actor.ownerID(),
              requestID,
              amount,
              clock.instant());
          return null;
        });
  }

  void start(CloudActor actor, UUID requestID) {
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          if (tx.one(
                  "SELECT id FROM sessions WHERE id = ? AND owner_id = ? AND device_id = ? AND revoked = 0 AND access_expires > ?",
                  r -> r.getString(1),
                  actor.sessionID(),
                  actor.ownerID(),
                  actor.deviceID(),
                  clock.instant())
              .isEmpty()) throw new CloudFailure(401, "session_expired");
          if (tx.execute(
                  "UPDATE model_usage SET state = 'RUNNING' WHERE owner_id = ? AND request_id = ? AND state = 'RESERVED'",
                  actor.ownerID(),
                  requestID)
              != 1) throw new CloudFailure(409, "generation_already_started");
          return null;
        });
  }

  void abandonReserved(CloudActor actor, UUID requestID) {
    database.transact(
        tx -> {
          tx.execute(
              "UPDATE model_usage SET state = 'SETTLED', actual = 0 WHERE owner_id = ? AND request_id = ? AND state = 'RESERVED'",
              actor.ownerID(),
              requestID);
          return null;
        });
  }

  public void settle(CloudActor actor, UUID requestID, Long actual) {
    if (actual != null && actual < 0) throw new CloudFailure(400, "invalid_usage");
    database.transact(
        tx -> {
          var old =
              tx.one(
                      "SELECT state, actual FROM model_usage WHERE owner_id = ? AND request_id = ?",
                      r ->
                          new Object[] {
                            r.getString(1), r.getObject(2) == null ? null : r.getLong(2)
                          },
                      actor.ownerID(),
                      requestID)
                  .orElseThrow(() -> new CloudFailure(404, "usage_not_found"));
          String state = actual == null ? "UNKNOWN" : "SETTLED";
          if (old[0].equals("SETTLED")) {
            if (!Objects.equals(old[1], actual)) throw new CloudFailure(409, "usage_conflict");
            return null;
          }
          tx.execute(
              "UPDATE model_usage SET actual = ?, state = ? WHERE owner_id = ? AND request_id = ?",
              actual,
              state,
              actor.ownerID(),
              requestID);
          return null;
        });
  }

  public Usage usage(CloudActor actor) {
    long used =
        database.transact(
            tx -> {
              CloudDevices.requireActive(tx, actor);
              return tx.one(
                      "SELECT COALESCE(SUM(COALESCE(actual, reserved)), 0) FROM model_usage WHERE owner_id = ? AND created_at >= ?",
                      r -> r.getLong(1),
                      actor.ownerID(),
                      day())
                  .orElse(0L);
            });
    return new Usage(limit, used, Math.max(0, limit - used));
  }

  private Instant day() {
    return clock
        .instant()
        .atZone(ZoneOffset.UTC)
        .toLocalDate()
        .atStartOfDay(ZoneOffset.UTC)
        .toInstant();
  }
}
