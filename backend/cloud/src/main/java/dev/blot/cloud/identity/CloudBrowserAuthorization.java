package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.CloudDatabase;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;

/** Short-lived authorization codes bind the browser identity to one native PKCE attempt. */
public final class CloudBrowserAuthorization {
  public record Code(String code, String expiresAt) {}

  private static final Map<String, String> CALLBACKS =
      Map.of(
          "blot-macos", "blot-agent-macos:/oauth/account",
          "blot-ios", "blot-agent-ios:/oauth/account");
  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final CloudSessions sessions;
  private final Clock clock;

  public CloudBrowserAuthorization(
      CloudDatabase database, CloudTokens tokens, CloudSessions sessions, Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.sessions = sessions;
    this.clock = clock;
  }

  public Code issue(CloudActor actor, String clientID, String redirectURI, String challenge) {
    validateClient(clientID, redirectURI);
    if (challenge == null || !challenge.matches("[A-Za-z0-9_-]{43}")) throw invalid();
    String code = tokens.random();
    var expires = clock.instant().plusSeconds(60);
    database.transact(
        tx -> {
          // A stale browser request cannot mint a code after its session was revoked.
          boolean active =
              tx.one(
                      "SELECT id FROM sessions WHERE id = ? AND revoked = 0 AND access_expires > ?",
                      r -> r.getString(1),
                      actor.sessionID(),
                      clock.instant())
                  .isPresent();
          if (!active) throw invalid();
          tx.execute("DELETE FROM browser_authorizations WHERE expires <= ?", clock.instant());
          tx.execute(
              "INSERT INTO browser_authorizations(code_hash, session_id, owner_id, client_id, redirect_uri, challenge, expires, bootstrap_allowed) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              tokens.digest(code),
              actor.sessionID(),
              actor.ownerID(),
              clientID,
              redirectURI,
              challenge,
              expires,
              actor.bootstrapAllowed() ? 1 : 0);
          return null;
        });
    return new Code(code, expires.toString());
  }

  public CloudSessions.Tokens exchange(
      String code, String verifier, String clientID, String redirectURI) {
    validateClient(clientID, redirectURI);
    if (code == null
        || !code.matches("[A-Za-z0-9_-]{43}")
        || verifier == null
        || !verifier.matches("[A-Za-z0-9._~-]{43,128}")) throw invalid();
    String challenge;
    try {
      challenge =
          Base64.getUrlEncoder()
              .withoutPadding()
              .encodeToString(
                  MessageDigest.getInstance("SHA-256")
                      .digest(verifier.getBytes(StandardCharsets.US_ASCII)));
    } catch (java.security.NoSuchAlgorithmException impossible) {
      throw new IllegalStateException(impossible);
    }
    String expectedChallenge = challenge;
    return database.transact(
        tx -> {
          var saved =
              tx.one(
                      "SELECT b.owner_id, b.challenge, b.bootstrap_allowed FROM browser_authorizations b JOIN sessions s ON s.id = b.session_id JOIN accounts a ON a.id = b.owner_id WHERE b.code_hash = ? AND b.client_id = ? AND b.redirect_uri = ? AND b.expires > ? AND s.revoked = 0 AND a.verified = 1",
                      r -> new String[] {r.getString(1), r.getString(2), r.getString(3)},
                      tokens.digest(code),
                      clientID,
                      redirectURI,
                      clock.instant())
                  .orElseThrow(CloudBrowserAuthorization::invalid);
          if (!tokens.equal(saved[1], expectedChallenge)) throw invalid();
          if (tx.execute(
                  "DELETE FROM browser_authorizations WHERE code_hash = ?", tokens.digest(code))
              != 1) throw invalid();
          return sessions.create(tx, UUID.fromString(saved[0]), "1".equals(saved[2]));
        });
  }

  private static void validateClient(String clientID, String redirectURI) {
    if (clientID == null || redirectURI == null || !redirectURI.equals(CALLBACKS.get(clientID)))
      throw invalid();
  }

  private static CloudFailure invalid() {
    return new CloudFailure(401, "browser_authorization_invalid");
  }
}
