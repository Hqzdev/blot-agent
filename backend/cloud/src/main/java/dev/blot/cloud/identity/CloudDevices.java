package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudDevices {
  public record Registration(
      UUID id,
      String name,
      String kind,
      byte[] signingKey,
      byte[] encryptionKey,
      byte[] signature) {}

  public record Certificate(
      UUID workspaceID,
      UUID pairingID,
      UUID signerID,
      long epoch,
      byte[] wrappedKeys,
      byte[] signature) {}

  public record Device(
      UUID id,
      String name,
      String kind,
      byte[] signingKey,
      byte[] encryptionKey,
      boolean revoked,
      Certificate certificate) {
    public Device(
        UUID id,
        String name,
        String kind,
        byte[] signingKey,
        byte[] encryptionKey,
        boolean revoked) {
      this(id, name, kind, signingKey, encryptionKey, revoked, null);
    }
  }

  private final CloudDatabase database;
  private final Clock clock;

  public CloudDevices(CloudDatabase database, Clock clock) {
    this.database = database;
    this.clock = clock;
  }

  public Device bootstrap(CloudActor actor, Registration registration) {
    validate(registration);
    CloudDeviceProof.verify(
        registration.signingKey(),
        CloudDeviceProof.message(
            "BLOT-DEVICE-BOOTSTRAP-1",
            List.of(actor.sessionID(), actor.workspaceID(), registration.id()),
            List.of(registration.signingKey(), registration.encryptionKey())),
        registration.signature());
    return database.transact(
        tx -> {
          boolean allowed =
              tx.one(
                      "SELECT bootstrap_used FROM accounts WHERE id = ? AND verified = 1",
                      r -> r.getInt(1) == 0,
                      actor.ownerID())
                  .orElse(false);
          if (!allowed || !actor.bootstrapAllowed() || actor.deviceID() != null)
            throw new CloudFailure(403, "device_pairing_required");
          tx.execute(
              "INSERT INTO devices(id, owner_id, workspace_id, name, kind, signing_key, encryption_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              registration.id(),
              actor.ownerID(),
              actor.workspaceID(),
              registration.name(),
              registration.kind(),
              registration.signingKey(),
              registration.encryptionKey(),
              clock.instant());
          tx.execute("UPDATE accounts SET bootstrap_used = 1 WHERE id = ?", actor.ownerID());
          tx.execute(
              "UPDATE sessions SET device_id = ?, bootstrap_allowed = 0 WHERE id = ?",
              registration.id(),
              actor.sessionID());
          return new Device(
              registration.id(),
              registration.name(),
              registration.kind(),
              registration.signingKey(),
              registration.encryptionKey(),
              false);
        });
  }

  public List<Device> list(CloudActor actor) {
    return database.transact(
        tx -> {
          requireActive(tx, actor);
          return tx.query(
              "SELECT d.id, d.name, d.kind, d.signing_key, d.encryption_key, d.revoked, p.id, p.initiator_id, p.approved_epoch, p.wrapped_keys, p.approval_signature FROM devices d LEFT JOIN pairings p ON p.candidate_id = d.id AND p.approved = 1 WHERE d.owner_id = ? AND d.workspace_id = ? ORDER BY d.created_at, d.id",
              r ->
                  new Device(
                      UUID.fromString(r.getString(1)),
                      r.getString(2),
                      r.getString(3),
                      r.getBytes(4),
                      r.getBytes(5),
                      r.getInt(6) != 0,
                      r.getString(7) == null
                          ? null
                          : new Certificate(
                              actor.workspaceID(),
                              UUID.fromString(r.getString(7)),
                              UUID.fromString(r.getString(8)),
                              r.getLong(9),
                              r.getBytes(10),
                              r.getBytes(11))),
              actor.ownerID(),
              actor.workspaceID());
        });
  }

  public static void requireActive(CloudTransaction tx, CloudActor actor) {
    if (actor.deviceID() == null
        || tx.one(
                "SELECT id FROM devices WHERE id = ? AND owner_id = ? AND workspace_id = ? AND revoked = 0",
                r -> r.getString(1),
                actor.deviceID(),
                actor.ownerID(),
                actor.workspaceID())
            .isEmpty()) throw new CloudFailure(403, "device_revoked");
  }

  public static void validate(Registration registration) {
    if (registration == null
        || registration.id() == null
        || registration.name() == null
        || registration.name().isBlank()
        || registration.name().length() > 200
        || (registration.kind() == null
            || !Set.of("DESKTOP", "PHONE").contains(registration.kind())))
      throw new CloudFailure(400, "invalid_device");
    CloudDeviceProof.key(registration.signingKey());
    CloudDeviceProof.key(registration.encryptionKey());
  }
}
