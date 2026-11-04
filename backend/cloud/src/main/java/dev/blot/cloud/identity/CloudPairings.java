package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

public final class CloudPairings {
  public record Invite(
      UUID id,
      UUID workspaceID,
      UUID initiatorID,
      String secret,
      byte[] initiatorSigningKey,
      byte[] initiatorEncryptionKey,
      String expiresAt) {}

  public record Status(UUID id, String state, CloudDevices.Device candidate, String expiresAt) {}

  public record Approved(
      UUID deviceID, long epoch, byte[] wrappedKeys, UUID signerID, byte[] signature) {}

  public record Approval(
      UUID pairingID, UUID candidateID, long epoch, byte[] wrappedKeys, byte[] signature) {}

  private record Pending(
      UUID owner,
      UUID workspace,
      UUID initiator,
      String secretHash,
      long expires,
      UUID candidate,
      byte[] signing,
      byte[] encryption,
      String name,
      String kind,
      UUID session,
      boolean approved,
      long epoch,
      byte[] wrapped,
      byte[] signature) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final Clock clock;

  public CloudPairings(CloudDatabase database, CloudTokens tokens, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.clock = clock;
  }

  public Invite start(CloudActor actor) {
    UUID id = UUID.randomUUID();
    String secret = tokens.random();
    Instant expires = clock.instant().plusSeconds(300);
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          byte[][] key =
              tx.one(
                      "SELECT signing_key, encryption_key FROM devices WHERE id = ?",
                      r -> new byte[][] {r.getBytes(1), r.getBytes(2)},
                      actor.deviceID())
                  .orElseThrow();
          tx.execute("DELETE FROM pairings WHERE expires < ? AND approved = 0", clock.instant());
          tx.execute(
              "INSERT INTO pairings(id, owner_id, workspace_id, initiator_id, secret_hash, expires) VALUES (?, ?, ?, ?, ?, ?)",
              id,
              actor.ownerID(),
              actor.workspaceID(),
              actor.deviceID(),
              tokens.digest(secret),
              expires);
          return new Invite(
              id,
              actor.workspaceID(),
              actor.deviceID(),
              secret,
              key[0],
              key[1],
              expires.toString());
        });
  }

  public Status claim(
      CloudActor actor, UUID pairingID, String secret, CloudDevices.Registration candidate) {
    CloudDevices.validate(candidate);
    if (secret == null || secret.length() > 128 || actor.deviceID() != null)
      throw new CloudFailure(403, "pairing_denied");
    return database.transact(
        tx -> {
          Pending pending = require(tx, pairingID, actor.ownerID());
          if (pending.expires() <= clock.millis() || pending.approved())
            throw new CloudFailure(410, "pairing_expired");
          if (!tokens.equal(pending.secretHash(), tokens.digest(secret)))
            throw new CloudFailure(403, "pairing_denied");
          CloudDeviceProof.verify(
              candidate.signingKey(),
              CloudDeviceProof.message(
                  "BLOT-PAIR-CLAIM-1",
                  List.of(pending.workspace(), pairingID, candidate.id()),
                  List.of(
                      candidate.signingKey(),
                      candidate.encryptionKey(),
                      secret.getBytes(StandardCharsets.US_ASCII))),
              candidate.signature());
          if (pending.candidate() != null) {
            if (!pending.candidate().equals(candidate.id())
                || !pending.session().equals(actor.sessionID())
                || !Arrays.equals(pending.signing(), candidate.signingKey())
                || !Arrays.equals(pending.encryption(), candidate.encryptionKey()))
              throw new CloudFailure(409, "pairing_already_claimed");
            return status(pairingID, pending);
          }
          if (tx.one("SELECT id FROM devices WHERE id = ?", r -> r.getString(1), candidate.id())
              .isPresent()) throw new CloudFailure(409, "device_id_exists");
          tx.execute(
              "UPDATE pairings SET candidate_id = ?, candidate_signing = ?, candidate_encryption = ?, candidate_name = ?, candidate_kind = ?, claimant_session_id = ? WHERE id = ?",
              candidate.id(),
              candidate.signingKey(),
              candidate.encryptionKey(),
              candidate.name(),
              candidate.kind(),
              actor.sessionID(),
              pairingID);
          return status(pairingID, require(tx, pairingID, actor.ownerID()));
        });
  }

  public Status inspect(CloudActor actor, UUID id) {
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          Pending pending = require(tx, id, actor.ownerID());
          if (!pending.initiator().equals(actor.deviceID()))
            throw new CloudFailure(403, "pairing_denied");
          return status(id, pending);
        });
  }

  public Approved approve(CloudActor actor, Approval approval) {
    if (approval == null
        || approval.wrappedKeys() == null
        || approval.wrappedKeys().length < 32
        || approval.wrappedKeys().length > 131_072)
      throw new CloudFailure(400, "invalid_key_grant");
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          Pending pending = require(tx, approval.pairingID(), actor.ownerID());
          if (!pending.initiator().equals(actor.deviceID())
              || pending.candidate() == null
              || !pending.candidate().equals(approval.candidateID()))
            throw new CloudFailure(403, "pairing_denied");
          if (pending.approved()) {
            if (pending.epoch() != approval.epoch()
                || !Arrays.equals(pending.wrapped(), approval.wrappedKeys())
                || !Arrays.equals(pending.signature(), approval.signature()))
              throw new CloudFailure(409, "command_conflict");
            return approved(pending);
          }
          if (pending.expires() <= clock.millis()) throw new CloudFailure(410, "pairing_expired");
          long epoch =
              tx.one(
                      "SELECT epoch FROM workspaces WHERE id = ?",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElseThrow();
          if (epoch != approval.epoch()) throw new CloudFailure(409, "key_epoch_required");
          long count =
              tx.one(
                      "SELECT COUNT(*) FROM devices WHERE workspace_id = ? AND revoked = 0",
                      r -> r.getLong(1),
                      actor.workspaceID())
                  .orElse(0L);
          if (count >= 16) throw new CloudFailure(409, "device_limit");
          byte[] ownerKey =
              tx.one(
                      "SELECT signing_key FROM devices WHERE id = ?",
                      r -> r.getBytes(1),
                      actor.deviceID())
                  .orElseThrow();
          CloudDeviceProof.verify(
              ownerKey,
              approvalMessage(
                  actor.workspaceID(),
                  approval.pairingID(),
                  actor.deviceID(),
                  pending.candidate(),
                  epoch,
                  pending.signing(),
                  pending.encryption(),
                  approval.wrappedKeys()),
              approval.signature());
          int bound =
              tx.execute(
                  "UPDATE sessions SET device_id = ?, bootstrap_allowed = 0 WHERE id = ? AND owner_id = ? AND revoked = 0 AND device_id IS NULL AND access_expires > ?",
                  pending.candidate(),
                  pending.session(),
                  actor.ownerID(),
                  clock.instant());
          if (bound != 1) throw new CloudFailure(409, "pairing_session_expired");
          tx.execute(
              "INSERT INTO devices(id, owner_id, workspace_id, name, kind, signing_key, encryption_key, certificate, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
              pending.candidate(),
              actor.ownerID(),
              actor.workspaceID(),
              pending.name(),
              pending.kind(),
              pending.signing(),
              pending.encryption(),
              approval.signature(),
              clock.instant());
          tx.execute(
              "UPDATE pairings SET approved = 1, approved_epoch = ?, wrapped_keys = ?, approval_signature = ? WHERE id = ?",
              epoch,
              approval.wrappedKeys(),
              approval.signature(),
              approval.pairingID());
          tx.execute(
              "INSERT INTO device_key_grants(device_id, epoch, ciphertext, signer_id, signature) VALUES (?, ?, ?, ?, ?)",
              pending.candidate(),
              epoch,
              approval.wrappedKeys(),
              actor.deviceID(),
              approval.signature());
          return approved(require(tx, approval.pairingID(), actor.ownerID()));
        });
  }

  public Approved result(CloudActor actor, UUID pairingID) {
    return database.transact(
        tx -> {
          Pending pending = require(tx, pairingID, actor.ownerID());
          if (pending.session() == null || !pending.session().equals(actor.sessionID()))
            throw new CloudFailure(403, "pairing_denied");
          if (!pending.approved())
            throw new CloudFailure(
                pending.expires() <= clock.millis() ? 410 : 409,
                pending.expires() <= clock.millis()
                    ? "pairing_expired"
                    : "pairing_waiting_confirmation");
          return approved(pending);
        });
  }

  public static byte[] approvalMessage(
      UUID workspace,
      UUID pairing,
      UUID initiator,
      UUID candidate,
      long epoch,
      byte[] signingKey,
      byte[] encryptionKey,
      byte[] wrappedKeys) {
    return CloudDeviceProof.message(
        "BLOT-PAIR-APPROVE-1",
        List.of(workspace, pairing, initiator, candidate),
        List.of(
            ByteBuffer.allocate(8).putLong(epoch).array(), signingKey, encryptionKey, wrappedKeys));
  }

  private Pending require(CloudTransaction tx, UUID id, UUID owner) {
    return tx.one(
            "SELECT owner_id, workspace_id, initiator_id, secret_hash, expires, candidate_id, candidate_signing, candidate_encryption, candidate_name, candidate_kind, claimant_session_id, approved, approved_epoch, wrapped_keys, approval_signature FROM pairings WHERE id = ? AND owner_id = ?",
            r ->
                new Pending(
                    UUID.fromString(r.getString(1)),
                    UUID.fromString(r.getString(2)),
                    UUID.fromString(r.getString(3)),
                    r.getString(4),
                    r.getLong(5),
                    uuid(r.getString(6)),
                    r.getBytes(7),
                    r.getBytes(8),
                    r.getString(9),
                    r.getString(10),
                    uuid(r.getString(11)),
                    r.getInt(12) != 0,
                    r.getLong(13),
                    r.getBytes(14),
                    r.getBytes(15)),
            id,
            owner)
        .orElseThrow(() -> new CloudFailure(404, "pairing_not_found"));
  }

  private Status status(UUID id, Pending pending) {
    var candidate =
        pending.candidate() == null
            ? null
            : new CloudDevices.Device(
                pending.candidate(),
                pending.name(),
                pending.kind(),
                pending.signing(),
                pending.encryption(),
                false);
    return new Status(
        id,
        pending.approved()
            ? "APPROVED"
            : pending.expires() <= clock.millis()
                ? "EXPIRED"
                : pending.candidate() == null ? "WAITING_CLAIM" : "WAITING_CONFIRMATION",
        candidate,
        Instant.ofEpochMilli(pending.expires()).toString());
  }

  private Approved approved(Pending pending) {
    return new Approved(
        pending.candidate(),
        pending.epoch(),
        pending.wrapped(),
        pending.initiator(),
        pending.signature());
  }

  private UUID uuid(String value) {
    return value == null ? null : UUID.fromString(value);
  }
}
