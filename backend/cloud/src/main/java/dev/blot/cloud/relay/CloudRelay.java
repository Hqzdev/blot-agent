package dev.blot.cloud.relay;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudRelay {
  public record Delivery(long sequence, CloudPacket packet) {}

  public record Batch(List<Delivery> deliveries, long cursor, boolean hasMore) {}

  private final CloudDatabase database;
  private final JsonCodec json;
  private final CloudTokens tokens;
  private final Clock clock;
  private final long maximumBytes;

  public CloudRelay(CloudDatabase database, JsonCodec json, CloudTokens tokens, Clock clock) {
    this(database, json, tokens, clock, 536_870_912L);
  }

  public CloudRelay(
      CloudDatabase database, JsonCodec json, CloudTokens tokens, Clock clock, long maximumBytes) {
    if (maximumBytes < 1) throw new IllegalArgumentException("Invalid relay quota");
    this.database = database;
    this.json = json;
    this.tokens = tokens;
    this.clock = clock;
    this.maximumBytes = maximumBytes;
  }

  public UUID upload(CloudActor actor, CloudPacket packet) {
    if (packet == null
        || !actor.workspaceID().equals(packet.workspaceID())
        || !Objects.equals(actor.deviceID(), packet.originDeviceID()))
      throw new CloudFailure(403, "packet_owner_mismatch");
    String serialized = json.write(packet);
    String digest = tokens.digest(serialized);
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          byte[] key =
              tx.one(
                      "SELECT signing_key FROM devices WHERE id = ?",
                      r -> r.getBytes(1),
                      actor.deviceID())
                  .orElseThrow();
          packet.verify(key);
          var existing =
              tx.one(
                  "SELECT digest FROM relay_receipts WHERE workspace_id = ? AND (change_id = ? OR (origin_device = ? AND origin_sequence = ?))",
                  r -> r.getString(1),
                  actor.workspaceID(),
                  packet.changeID(),
                  actor.deviceID(),
                  packet.sequence());
          if (existing.isPresent()) {
            if (!tokens.equal(existing.get(), digest))
              throw new CloudFailure(409, "command_conflict");
            return packet.changeID();
          }
          long epoch =
              tx.one(
                      "SELECT epoch FROM workspaces WHERE id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElseThrow();
          if (packet.keyEpoch() != epoch) throw new CloudFailure(409, "key_epoch_required");
          long last =
              tx.one(
                      "SELECT COALESCE(MAX(origin_sequence), 0) FROM relay_receipts WHERE workspace_id = ? AND origin_device = ?",
                      r -> r.getLong(1),
                      actor.workspaceID(),
                      actor.deviceID())
                  .orElse(0L);
          if (last == Long.MAX_VALUE || packet.sequence() != last + 1)
            throw new CloudFailure(409, "sequence_gap");
          long retained =
              tx.one(
                      "SELECT COALESCE(SUM(length(packet)), 0) FROM relay_packets WHERE workspace_id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElse(0L);
          if (retained > maximumBytes - serialized.length())
            throw new CloudFailure(429, "relay_quota_exceeded");
          tx.execute(
              "INSERT INTO relay_packets(workspace_id, origin_device, change_id, origin_sequence, epoch, packet, digest, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              actor.workspaceID(),
              actor.deviceID(),
              packet.changeID(),
              packet.sequence(),
              packet.keyEpoch(),
              serialized,
              digest,
              clock.instant());
          long delivery = tx.one("SELECT last_insert_rowid()", r -> r.getLong(1)).orElseThrow();
          tx.execute(
              "INSERT INTO relay_receipts(change_id, workspace_id, origin_device, origin_sequence, delivery_sequence, digest) VALUES (?, ?, ?, ?, ?, ?)",
              packet.changeID(),
              actor.workspaceID(),
              actor.deviceID(),
              packet.sequence(),
              delivery,
              digest);
          return packet.changeID();
        });
  }

  public boolean accepted(CloudActor actor, UUID changeID) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          return tx.one(
                  "SELECT change_id FROM relay_receipts WHERE change_id = ? AND workspace_id = ? AND origin_device = ?",
                  r -> r.getString(1),
                  changeID,
                  actor.workspaceID(),
                  actor.deviceID())
              .isPresent();
        });
  }

  public Batch pull(CloudActor actor, long after, int limit) {
    if (after < 0 || limit < 1 || limit > 500) throw new CloudFailure(400, "invalid_cursor");
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          long floor =
              tx.one(
                      "SELECT sequence FROM relay_floor WHERE workspace_id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElse(0L);
          long head = head(tx, actor.workspaceID());
          if (after < floor) throw new CloudFailure(409, "replay_unavailable");
          if (after > head) throw new CloudFailure(409, "cursor_ahead");
          var entries =
              tx.query(
                  "SELECT delivery_seq, packet FROM relay_packets WHERE workspace_id = ? AND delivery_seq > ? ORDER BY delivery_seq LIMIT ?",
                  r -> new Delivery(r.getLong(1), json.read(r.getString(2), CloudPacket.class)),
                  actor.workspaceID(),
                  after,
                  limit);
          long cursor = entries.isEmpty() ? head : entries.getLast().sequence();
          return new Batch(entries, cursor, cursor < head);
        });
  }

  public void acknowledge(CloudActor actor, long cursor) {
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          if (cursor < 0 || cursor > head(tx, actor.workspaceID()))
            throw new CloudFailure(400, "invalid_cursor");
          tx.execute(
              "INSERT INTO relay_acks(workspace_id, device_id, sequence) VALUES (?, ?, ?) ON CONFLICT(workspace_id, device_id) DO UPDATE SET sequence = MAX(sequence, excluded.sequence)",
              actor.workspaceID(),
              actor.deviceID(),
              cursor);
          return null;
        });
  }

  public void purgeExpired() {
    database.transact(
        tx -> {
          long cutoff = clock.instant().minus(Duration.ofDays(30)).toEpochMilli();
          var expired =
              tx.query(
                  "SELECT workspace_id, MAX(delivery_seq) FROM relay_packets WHERE created_at < ? GROUP BY workspace_id",
                  r -> new Object[] {r.getString(1), r.getLong(2)},
                  cutoff);
          for (Object[] value : expired)
            tx.execute(
                "INSERT INTO relay_floor(workspace_id, sequence) VALUES (?, ?) ON CONFLICT(workspace_id) DO UPDATE SET sequence = MAX(sequence, excluded.sequence)",
                value[0],
                value[1]);
          tx.execute("DELETE FROM relay_packets WHERE created_at < ?", cutoff);
          return null;
        });
  }

  private long head(CloudTransaction tx, UUID workspace) {
    return tx.one(
            "SELECT COALESCE(MAX(delivery_sequence), 0) FROM relay_receipts WHERE workspace_id = ?",
            r -> r.getLong(1),
            workspace)
        .orElse(0L);
  }
}
