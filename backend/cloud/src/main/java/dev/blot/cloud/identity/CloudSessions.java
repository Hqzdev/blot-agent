package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudSessions {
  public record Tokens(
      UUID sessionID,
      String accessToken,
      String refreshToken,
      String expiresAt,
      UUID ownerID,
      UUID workspaceID,
      UUID deviceID,
      boolean bootstrapAllowed) {}

  public record BindingChallenge(String nonce, String expiresAt) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final Clock clock;

  public CloudSessions(CloudDatabase database, CloudTokens tokens, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.clock = clock;
  }

  public Tokens create(CloudTransaction tx, UUID owner, boolean bootstrapAllowed) {
    UUID workspace =
        tx.one(
                "SELECT id FROM workspaces WHERE owner_id = ?",
                r -> UUID.fromString(r.getString(1)),
                owner)
            .orElseThrow(() -> new CloudFailure(403, "workspace_unavailable"));
    UUID sessionID = UUID.randomUUID();
    String access = tokens.random(), refresh = tokens.random();
    Instant expires = clock.instant().plusSeconds(900);
    tx.execute(
        "INSERT INTO sessions(id, owner_id, access_hash, refresh_hash, access_expires, refresh_expires, bootstrap_allowed) VALUES (?, ?, ?, ?, ?, ?, ?)",
        sessionID,
        owner,
        tokens.digest(access),
        tokens.digest(refresh),
        expires,
        clock.instant().plus(Duration.ofDays(30)),
        bootstrapAllowed ? 1 : 0);
    return new Tokens(
        sessionID, access, refresh, expires.toString(), owner, workspace, null, bootstrapAllowed);
  }

  public CloudActor require(String authorization, boolean requireDevice) {
    if (authorization == null || !authorization.matches("Bearer [A-Za-z0-9_-]{43}"))
      throw new CloudFailure(401, "session_required");
    return database.transact(
        tx -> {
          var actor =
              tx.one(
                      "SELECT s.owner_id, w.id, s.id, s.device_id, s.bootstrap_allowed FROM sessions s JOIN accounts a ON a.id = s.owner_id JOIN workspaces w ON w.owner_id = s.owner_id LEFT JOIN devices d ON d.id = s.device_id WHERE s.access_hash = ? AND s.revoked = 0 AND s.access_expires > ? AND a.verified = 1 AND (s.device_id IS NULL OR d.revoked = 0)",
                      r ->
                          new CloudActor(
                              UUID.fromString(r.getString(1)),
                              UUID.fromString(r.getString(2)),
                              UUID.fromString(r.getString(3)),
                              r.getString(4) == null ? null : UUID.fromString(r.getString(4)),
                              r.getInt(5) != 0),
                      tokens.digest(authorization.substring(7)),
                      clock.instant())
                  .orElseThrow(() -> new CloudFailure(401, "session_expired"));
          if (requireDevice && actor.deviceID() == null)
            throw new CloudFailure(403, "device_pairing_required");
          return actor;
        });
  }

  public Tokens refresh(String refreshToken) {
    if (refreshToken == null || refreshToken.length() > 128)
      throw new CloudFailure(401, "session_expired");
    return database.transact(
        tx -> {
          var old =
              tx.one(
                      "SELECT s.id, s.owner_id, s.device_id, w.id, s.bootstrap_allowed FROM sessions s JOIN workspaces w ON w.owner_id = s.owner_id LEFT JOIN devices d ON d.id = s.device_id WHERE s.refresh_hash = ? AND s.revoked = 0 AND s.refresh_expires > ? AND (s.device_id IS NULL OR d.revoked = 0)",
                      r ->
                          new String[] {
                            r.getString(1),
                            r.getString(2),
                            r.getString(3),
                            r.getString(4),
                            r.getString(5)
                          },
                      tokens.digest(refreshToken),
                      clock.instant())
                  .orElseThrow(() -> new CloudFailure(401, "session_expired"));
          String access = tokens.random(), refresh = tokens.random();
          Instant expires = clock.instant().plusSeconds(900);
          tx.execute(
              "UPDATE sessions SET access_hash = ?, refresh_hash = ?, access_expires = ? WHERE id = ?",
              tokens.digest(access),
              tokens.digest(refresh),
              expires,
              old[0]);
          return new Tokens(
              UUID.fromString(old[0]),
              access,
              refresh,
              expires.toString(),
              UUID.fromString(old[1]),
              UUID.fromString(old[3]),
              old[2] == null ? null : UUID.fromString(old[2]),
              "1".equals(old[4]));
        });
  }

  public BindingChallenge challenge(CloudActor actor) {
    String nonce = tokens.random();
    Instant expires = clock.instant().plusSeconds(300);
    database.transact(
        tx -> {
          tx.execute(
              "INSERT INTO binding_challenges(session_id, nonce_hash, expires) VALUES (?, ?, ?) ON CONFLICT(session_id) DO UPDATE SET nonce_hash = excluded.nonce_hash, expires = excluded.expires",
              actor.sessionID(),
              tokens.digest(nonce),
              expires);
          return null;
        });
    return new BindingChallenge(nonce, expires.toString());
  }

  public void bind(CloudActor actor, UUID deviceID, String nonce, byte[] signature) {
    if (nonce == null || nonce.length() > 128) throw new CloudFailure(403, "device_proof_invalid");
    database.transact(
        tx -> {
          var stored =
              tx.one(
                      "SELECT nonce_hash FROM binding_challenges WHERE session_id = ? AND expires > ?",
                      r -> r.getString(1),
                      actor.sessionID(),
                      clock.instant())
                  .orElseThrow(() -> new CloudFailure(403, "challenge_expired"));
          if (!tokens.equal(stored, tokens.digest(nonce)))
            throw new CloudFailure(403, "device_proof_invalid");
          byte[] key =
              tx.one(
                      "SELECT signing_key FROM devices WHERE id = ? AND owner_id = ? AND revoked = 0",
                      r -> r.getBytes(1),
                      deviceID,
                      actor.ownerID())
                  .orElseThrow(() -> new CloudFailure(403, "device_revoked"));
          CloudDeviceProof.verify(
              key,
              CloudDeviceProof.message(
                  "BLOT-SESSION-BIND-1",
                  List.of(actor.sessionID(), deviceID),
                  List.of(nonce.getBytes(java.nio.charset.StandardCharsets.US_ASCII))),
              signature);
          tx.execute(
              "UPDATE sessions SET device_id = ?, bootstrap_allowed = 0 WHERE id = ?",
              deviceID,
              actor.sessionID());
          tx.execute("DELETE FROM binding_challenges WHERE session_id = ?", actor.sessionID());
          return null;
        });
  }

  public void logout(CloudActor actor) {
    database.transact(
        tx -> {
          tx.execute(
              "UPDATE sessions SET revoked = 1 WHERE id = ? AND owner_id = ?",
              actor.sessionID(),
              actor.ownerID());
          return null;
        });
  }

  public void revokeAll(CloudActor actor) {
    database.transact(
        tx -> {
          tx.execute("UPDATE sessions SET revoked = 1 WHERE owner_id = ?", actor.ownerID());
          return null;
        });
  }
}
