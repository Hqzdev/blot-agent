package dev.blot.cloud.relay;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

/** Coordinates donors; snapshot contents and the group key remain opaque to the server. */
public final class CloudSnapshots {
  public record Request(
      UUID requestID, UUID requesterDeviceID, long minimumCursor, String expiresAt) {}

  public record Offer(
      UUID requestID,
      UUID snapshotID,
      UUID donorDeviceID,
      long keyEpoch,
      long relayCursor,
      int byteCount,
      int chunkCount,
      String digest,
      byte[] packetSignature,
      byte[] signature) {
    public Offer {
      packetSignature = packetSignature == null ? null : packetSignature.clone();
      signature = signature == null ? null : signature.clone();
    }

    @Override
    public byte[] packetSignature() {
      return packetSignature == null ? null : packetSignature.clone();
    }

    @Override
    public byte[] signature() {
      return signature == null ? null : signature.clone();
    }
  }

  public record Status(Request request, Offer offer) {}

  private final CloudDatabase database;
  private final JsonCodec json;
  private final Clock clock;

  public CloudSnapshots(CloudDatabase database, JsonCodec json, Clock clock) {
    this.database = database;
    this.json = json;
    this.clock = clock;
  }

  public Status request(CloudActor actor, UUID id, long minimumCursor) {
    if (id == null || minimumCursor < 0) throw new CloudFailure(400, "invalid_snapshot_request");
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          var previous =
              tx.one(
                  "SELECT requester_id,minimum_cursor FROM snapshot_requests WHERE id = ?",
                  r -> new String[] {r.getString(1), r.getString(2)},
                  id);
          if (previous.isPresent()) {
            if (!previous.get()[0].equals(actor.deviceID().toString()))
              throw new CloudFailure(403, "snapshot_owner_mismatch");
            if (Long.parseLong(previous.get()[1]) != minimumCursor)
              throw new CloudFailure(409, "command_conflict");
            return status(tx, actor, id);
          }
          long head =
              tx.one(
                      "SELECT COALESCE(MAX(delivery_sequence),0) FROM relay_receipts WHERE workspace_id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElse(0L);
          if (minimumCursor > head) throw new CloudFailure(400, "invalid_cursor");
          long count =
              tx.one(
                      "SELECT COUNT(*) FROM snapshot_requests WHERE workspace_id = ? AND expires > ?",
                      r -> r.getLong(1),
                      actor.workspaceID(),
                      clock.instant())
                  .orElse(0L);
          if (count >= 1024) throw new CloudFailure(429, "snapshot_quota");
          tx.execute(
              "INSERT INTO snapshot_requests(id,workspace_id,requester_id,minimum_cursor,expires) VALUES (?,?,?,?,?)",
              id,
              actor.workspaceID(),
              actor.deviceID(),
              minimumCursor,
              clock.instant().plus(Duration.ofDays(30)));
          return status(tx, actor, id);
        });
  }

  public Status status(CloudActor actor, UUID id) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          return status(tx, actor, id);
        });
  }

  public List<Request> pending(CloudActor actor) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          return tx
              .query(
                  "SELECT s.id FROM snapshot_requests s JOIN devices d ON d.id = s.requester_id WHERE s.workspace_id = ? AND s.requester_id != ? AND s.expires > ? AND d.revoked = 0 ORDER BY s.expires LIMIT 1024",
                  r -> UUID.fromString(r.getString(1)),
                  actor.workspaceID(),
                  actor.deviceID(),
                  clock.instant())
              .stream()
              .map(id -> status(tx, actor, id))
              .filter(s -> s.offer() == null)
              .limit(50)
              .map(Status::request)
              .toList();
        });
  }

  public void publish(CloudActor actor, Offer offer) {
    if (offer == null
        || offer.requestID() == null
        || offer.snapshotID() == null
        || !Objects.equals(offer.donorDeviceID(), actor.deviceID())
        || offer.keyEpoch() < 1
        || offer.relayCursor() < 0
        || offer.byteCount() < 28
        || offer.byteCount() > 134_217_728
        || offer.chunkCount() != (offer.byteCount() + 262_143) / 262_144
        || offer.digest() == null
        || !offer.digest().matches("[0-9a-f]{64}")
        || offer.packetSignature() == null
        || offer.packetSignature().length < 8
        || offer.packetSignature().length > 80)
      throw new CloudFailure(400, "invalid_snapshot_offer");
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          Status status = status(tx, actor, offer.requestID());
          if (status.request().requesterDeviceID().equals(actor.deviceID()))
            throw new CloudFailure(403, "snapshot_owner_mismatch");
          byte[] publicKey =
              tx.one(
                      "SELECT signing_key FROM devices WHERE id = ?",
                      r -> r.getBytes(1),
                      actor.deviceID())
                  .orElseThrow();
          CloudDeviceProof.verify(publicKey, proof(actor.workspaceID(), offer), offer.signature());
          if (status.offer() != null) {
            if (!json.write(status.offer()).equals(json.write(offer)))
              throw new CloudFailure(409, "snapshot_offer_conflict");
            return null;
          }
          long epoch =
              tx.one(
                      "SELECT epoch FROM workspaces WHERE id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElseThrow();
          long ack =
              tx.one(
                      "SELECT sequence FROM relay_acks WHERE workspace_id = ? AND device_id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID(),
                      actor.deviceID())
                  .orElse(0L);
          if (offer.keyEpoch() != epoch) throw new CloudFailure(409, "key_epoch_required");
          if (offer.relayCursor() < status.request().minimumCursor() || offer.relayCursor() > ack)
            throw new CloudFailure(409, "snapshot_cursor_unavailable");
          var chunks =
              tx.query(
                  "SELECT chunk_index,chunk_count,length(ciphertext),creator_id FROM encrypted_blobs WHERE workspace_id = ? AND blob_id = ? AND created_at >= ? ORDER BY chunk_index",
                  r -> new Object[] {r.getInt(1), r.getInt(2), r.getInt(3), r.getString(4)},
                  actor.workspaceID(),
                  offer.snapshotID(),
                  clock.instant().minus(Duration.ofDays(30)));
          int bytes = 0;
          if (chunks.size() != offer.chunkCount())
            throw new CloudFailure(409, "snapshot_chunks_missing");
          for (int i = 0; i < chunks.size(); i++) {
            Object[] chunk = chunks.get(i);
            int expected = Math.min(262_144, offer.byteCount() - i * 262_144);
            if ((int) chunk[0] != i
                || (int) chunk[1] != offer.chunkCount()
                || (int) chunk[2] != expected
                || !chunk[3].equals(actor.deviceID().toString()))
              throw new CloudFailure(409, "snapshot_chunks_missing");
            bytes += (int) chunk[2];
          }
          if (bytes != offer.byteCount()) throw new CloudFailure(409, "snapshot_chunks_missing");
          tx.execute(
              "UPDATE snapshot_requests SET offer = ?, donor_id = ?, offer_epoch = ?, offer_cursor = ? WHERE id = ?",
              json.write(offer),
              actor.deviceID(),
              offer.keyEpoch(),
              offer.relayCursor(),
              offer.requestID());
          return null;
        });
  }

  public void purgeExpired() {
    database.transact(
        tx -> {
          tx.execute("DELETE FROM snapshot_requests WHERE expires <= ?", clock.instant());
          return null;
        });
  }

  private Status status(CloudTransaction tx, CloudActor actor, UUID id) {
    long floor =
        tx.one(
                "SELECT sequence FROM relay_floor WHERE workspace_id = ?",
                r -> r.getLong(1),
                actor.workspaceID())
            .orElse(0L);
    return tx.one(
            "SELECT s.requester_id,s.minimum_cursor,s.expires,s.offer,s.offer_cursor,s.offer_epoch,w.epoch,d.revoked FROM snapshot_requests s JOIN workspaces w ON w.id = s.workspace_id LEFT JOIN devices d ON d.id = s.donor_id JOIN devices receiver ON receiver.id = s.requester_id WHERE s.id = ? AND s.workspace_id = ? AND s.expires > ? AND receiver.revoked = 0",
            r -> {
              var request =
                  new Request(
                      id,
                      UUID.fromString(r.getString(1)),
                      Math.max(floor, r.getLong(2)),
                      Instant.ofEpochMilli(r.getLong(3)).toString());
              boolean usable =
                  r.getString(4) != null
                      && r.getLong(5) >= request.minimumCursor()
                      && r.getLong(6) == r.getLong(7)
                      && r.getInt(8) == 0;
              return new Status(request, usable ? json.read(r.getString(4), Offer.class) : null);
            },
            id,
            actor.workspaceID(),
            clock.instant())
        .orElseThrow(() -> new CloudFailure(404, "snapshot_request_unavailable"));
  }

  public static byte[] proof(UUID workspaceID, Offer offer) {
    return CloudDeviceProof.message(
        "BLOT-SNAPSHOT-OFFER-1",
        List.of(workspaceID, offer.requestID(), offer.snapshotID(), offer.donorDeviceID()),
        List.of(
            integer(offer.keyEpoch()),
            integer(offer.relayCursor()),
            integer(offer.byteCount()),
            integer(offer.chunkCount()),
            offer.digest().getBytes(StandardCharsets.US_ASCII),
            offer.packetSignature()));
  }

  private static byte[] integer(long value) {
    return java.nio.ByteBuffer.allocate(8).putLong(value).array();
  }
}
