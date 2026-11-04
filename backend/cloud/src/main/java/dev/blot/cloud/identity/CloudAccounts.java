package dev.blot.cloud.identity;

import dev.blot.application.ports.PasswordHasher;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudAccounts {
  public record Account(UUID id, String email, String name, boolean verified) {}

  private record Credentials(UUID id, String hash, boolean verified) {}

  private final CloudDatabase database;
  private final PasswordHasher hasher;
  private final CloudEmailChallenges challenges;
  private final CloudSessions sessions;
  private final Clock clock;
  private final String dummyHash;

  public CloudAccounts(
      CloudDatabase database,
      PasswordHasher hasher,
      CloudEmailChallenges challenges,
      CloudSessions sessions,
      Clock clock) {
    this.database = database;
    this.hasher = hasher;
    this.challenges = challenges;
    this.sessions = sessions;
    this.clock = clock;
    this.dummyHash = hasher.hash(UUID.randomUUID().toString());
  }

  public void register(String address, String password, String name) {
    String email = CloudTokens.email(address);
    CloudTokens.password(password);
    if (name == null || name.isBlank() || name.length() > 200)
      throw new CloudFailure(400, "invalid_name");
    String hash = hasher.hash(password);
    UUID owner =
        database.transact(
            tx -> {
              var existing =
                  tx.one(
                      "SELECT id FROM accounts WHERE email = ?",
                      r -> UUID.fromString(r.getString(1)),
                      email);
              if (existing.isPresent()) return existing.get();
              UUID id = UUID.randomUUID();
              tx.execute(
                  "INSERT INTO accounts(id, email, password_hash, name, created_at) VALUES (?, ?, ?, ?, ?)",
                  id,
                  email,
                  hash,
                  name.strip(),
                  clock.instant());
              tx.execute(
                  "INSERT INTO workspaces(id, owner_id) VALUES (?, ?)", UUID.randomUUID(), id);
              return id;
            });
    // Re-registration never changes an existing password, and does not expose account existence.
    challenges.send(owner, email, "verify", hash, name.strip());
  }

  public CloudSessions.Tokens verify(String address, String code) {
    String email = CloudTokens.email(address);
    UUID owner =
        database.transact(
            tx ->
                tx.one(
                        "SELECT id FROM accounts WHERE email = ?",
                        r -> UUID.fromString(r.getString(1)),
                        email)
                    .orElseThrow(() -> new CloudFailure(400, "code_expired_or_invalid")));
    return challenges.consume(
        owner,
        "verify",
        code,
        tx -> {
          boolean first =
              tx.one("SELECT verified FROM accounts WHERE id = ?", r -> r.getInt(1) == 0, owner)
                  .orElse(false);
          if (first) {
            var registration =
                tx.one(
                        "SELECT registration_hash, registration_name FROM email_challenges WHERE owner_id = ? AND purpose = 'verify'",
                        r -> new String[] {r.getString(1), r.getString(2)},
                        owner)
                    .orElseThrow(() -> new CloudFailure(400, "code_expired_or_invalid"));
            tx.execute(
                "UPDATE accounts SET password_hash = ?, name = ? WHERE id = ?",
                registration[0],
                registration[1],
                owner);
          }
          tx.execute("UPDATE accounts SET verified = 1 WHERE id = ?", owner);
          return sessions.create(tx, owner, first);
        });
  }

  public CloudSessions.Tokens login(String address, String password) {
    String email = CloudTokens.email(address);
    CloudTokens.password(password);
    var credentials =
        database.transact(
            tx ->
                tx.one(
                    "SELECT id, password_hash, verified FROM accounts WHERE email = ?",
                    r ->
                        new Credentials(
                            UUID.fromString(r.getString(1)), r.getString(2), r.getInt(3) != 0),
                    email));
    boolean matches =
        hasher.matches(password, credentials.map(Credentials::hash).orElse(dummyHash));
    if (!matches || credentials.isEmpty()) throw new CloudFailure(401, "wrong_credentials");
    Credentials account = credentials.get();
    if (!account.verified()) throw new CloudFailure(403, "email_unverified");
    return database.transact(tx -> sessions.create(tx, account.id(), false));
  }

  public void requestReset(String address) {
    String email = CloudTokens.email(address);
    challenges.allowResetRequest(email);
    var owner =
        database.transact(
            tx ->
                tx.one(
                    "SELECT id FROM accounts WHERE email = ?",
                    r -> UUID.fromString(r.getString(1)),
                    email));
    try {
      owner.ifPresent(id -> challenges.send(id, email, "reset"));
    } catch (RuntimeException failure) {
      if (!(failure instanceof WorkspaceFailure workspaceFailure
              && workspaceFailure.status() == 503)
          && !(failure instanceof CloudFailure cloudFailure && cloudFailure.status() == 503))
        throw failure;
      // The public response must not reveal account existence when SMTP is unavailable.
      System.getLogger(CloudAccounts.class.getName())
          .log(System.Logger.Level.WARNING, "Password reset delivery unavailable");
    }
  }

  public void reset(String address, String code, String password) {
    String email = CloudTokens.email(address);
    CloudTokens.password(password);
    UUID owner =
        database.transact(
            tx ->
                tx.one(
                        "SELECT id FROM accounts WHERE email = ?",
                        r -> UUID.fromString(r.getString(1)),
                        email)
                    .orElseThrow(() -> new CloudFailure(400, "code_expired_or_invalid")));
    String hash = hasher.hash(password);
    challenges.consume(
        owner,
        "reset",
        code,
        tx -> {
          tx.execute("UPDATE accounts SET password_hash = ? WHERE id = ?", hash, owner);
          tx.execute("UPDATE sessions SET revoked = 1 WHERE owner_id = ?", owner);
          return Boolean.TRUE;
        });
  }

  public Account me(CloudActor actor) {
    return database.transact(
        tx ->
            tx.one(
                    "SELECT id, email, name, verified FROM accounts WHERE id = ?",
                    r ->
                        new Account(
                            UUID.fromString(r.getString(1)),
                            r.getString(2),
                            r.getString(3),
                            r.getInt(4) != 0),
                    actor.ownerID())
                .orElseThrow(() -> new CloudFailure(401, "session_expired")));
  }
}
