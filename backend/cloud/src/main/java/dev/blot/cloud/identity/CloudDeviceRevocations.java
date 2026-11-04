package dev.blot.cloud.identity;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class CloudDeviceRevocations {
  public record Request(
      UUID commandID, UUID deviceID, long newEpoch, Map<UUID, byte[]> grants, byte[] signature) {}

  public record Result(long epoch, List<UUID> stoppedTasks) {}

  public record Manifest(
      UUID workspaceID,
      UUID signerID,
      UUID revokedDeviceID,
      long epoch,
      Map<UUID, byte[]> grants,
      byte[] signature) {}

  public record KeyGrant(long epoch, byte[] ciphertext, UUID signerID, byte[] signature) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final JsonCodec json;

  public CloudDeviceRevocations(CloudDatabase database, CloudTokens tokens, JsonCodec json) {
    this.database = database;
    this.tokens = tokens;
    this.json = json;
  }

  public Result revoke(CloudActor actor, Request request) {
    if (request == null
        || request.commandID() == null
        || request.deviceID() == null
        || request.grants() == null
        || request.grants().size() > 16
        || request.grants().values().stream()
            .anyMatch(v -> v == null || v.length < 32 || v.length > 131_072))
      throw new CloudFailure(400, "invalid_key_grant");
    byte[] message =
        message(
            actor.workspaceID(),
            actor.deviceID(),
            request.deviceID(),
            request.newEpoch(),
            request.grants());
    String digest = tokens.digest(message);
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          var old =
              tx.one(
                  "SELECT digest, epoch FROM device_revocations WHERE id = ? AND workspace_id = ?",
                  r -> new String[] {r.getString(1), r.getString(2)},
                  request.commandID(),
                  actor.workspaceID());
          if (old.isPresent()) {
            if (!old.get()[0].equals(digest)) throw new CloudFailure(409, "command_conflict");
            return new Result(
                Long.parseLong(old.get()[1]), stopped(tx, actor.workspaceID(), request.deviceID()));
          }
          var target =
              tx.one(
                      "SELECT revoked FROM devices WHERE id = ? AND workspace_id = ?",
                      r -> r.getInt(1),
                      request.deviceID(),
                      actor.workspaceID())
                  .orElseThrow(() -> new CloudFailure(404, "device_not_found"));
          if (target != 0) throw new CloudFailure(409, "device_already_revoked");
          long epoch =
              tx.one(
                      "SELECT epoch FROM workspaces WHERE id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElseThrow();
          if (epoch == Long.MAX_VALUE || request.newEpoch() != epoch + 1)
            throw new CloudFailure(409, "key_epoch_required");
          var recipients =
              new HashSet<>(
                  tx.query(
                      "SELECT id FROM devices WHERE workspace_id = ? AND revoked = 0 AND id != ?",
                      r -> UUID.fromString(r.getString(1)),
                      actor.workspaceID(),
                      request.deviceID()));
          if (!recipients.equals(request.grants().keySet()))
            throw new CloudFailure(400, "incomplete_key_rotation");
          byte[] ownerKey =
              tx.one(
                      "SELECT signing_key FROM devices WHERE id = ?",
                      r -> r.getBytes(1),
                      actor.deviceID())
                  .orElseThrow();
          CloudDeviceProof.verify(ownerKey, message, request.signature());
          tx.execute("UPDATE devices SET revoked = 1 WHERE id = ?", request.deviceID());
          tx.execute("UPDATE sessions SET revoked = 1 WHERE device_id = ?", request.deviceID());
          tx.execute(
              "UPDATE workspaces SET epoch = ? WHERE id = ?",
              request.newEpoch(),
              actor.workspaceID());
          tx.execute(
              "UPDATE task_assignments SET canceled = 1, lease_expires = NULL, holder_id = NULL WHERE workspace_id = ? AND executor_device = ?",
              actor.workspaceID(),
              request.deviceID());
          byte[] manifest =
              json.write(
                      new Manifest(
                          actor.workspaceID(),
                          actor.deviceID(),
                          request.deviceID(),
                          request.newEpoch(),
                          request.grants(),
                          request.signature()))
                  .getBytes(StandardCharsets.UTF_8);
          for (UUID recipient : recipients)
            tx.execute(
                "INSERT INTO device_key_grants(device_id, epoch, ciphertext, signer_id, signature) VALUES (?, ?, ?, ?, ?)",
                recipient,
                request.newEpoch(),
                manifest,
                actor.deviceID(),
                request.signature());
          tx.execute(
              "INSERT INTO device_revocations(id, workspace_id, target_id, epoch, digest) VALUES (?, ?, ?, ?, ?)",
              request.commandID(),
              actor.workspaceID(),
              request.deviceID(),
              request.newEpoch(),
              digest);
          return new Result(
              request.newEpoch(), stopped(tx, actor.workspaceID(), request.deviceID()));
        });
  }

  public List<KeyGrant> keys(CloudActor actor, long afterEpoch) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          return tx.query(
              "SELECT epoch, ciphertext, signer_id, signature FROM device_key_grants WHERE device_id = ? AND epoch > ? ORDER BY epoch",
              r ->
                  new KeyGrant(
                      r.getLong(1), r.getBytes(2), UUID.fromString(r.getString(3)), r.getBytes(4)),
              actor.deviceID(),
              afterEpoch);
        });
  }

  public static byte[] message(
      UUID workspace, UUID signer, UUID target, long epoch, Map<UUID, byte[]> grants) {
    var values = new ArrayList<byte[]>();
    values.add(ByteBuffer.allocate(8).putLong(epoch).array());
    grants.keySet().stream()
        .sorted(Comparator.comparing(UUID::toString))
        .forEach(
            id -> {
              values.add(
                  ByteBuffer.allocate(16)
                      .putLong(id.getMostSignificantBits())
                      .putLong(id.getLeastSignificantBits())
                      .array());
              values.add(grants.get(id));
            });
    return CloudDeviceProof.message(
        "BLOT-DEVICE-REVOKE-1", List.of(workspace, signer, target), values);
  }

  private List<UUID> stopped(CloudTransaction tx, UUID workspace, UUID device) {
    return tx.query(
        "SELECT id FROM task_assignments WHERE workspace_id = ? AND executor_device = ? AND canceled = 1",
        r -> UUID.fromString(r.getString(1)),
        workspace,
        device);
  }
}
