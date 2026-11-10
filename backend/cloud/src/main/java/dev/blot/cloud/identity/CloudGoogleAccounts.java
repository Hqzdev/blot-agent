package dev.blot.cloud.identity;

import dev.blot.application.ports.PasswordHasher;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.CloudDatabase;
import java.time.Clock;
import java.util.UUID;

/** Existing password accounts require an explicit linking flow, never an email-only merge. */
public final class CloudGoogleAccounts {
  private final CloudDatabase database;
  private final CloudGoogleIdentityVerifier verifier;
  private final CloudSessions sessions;
  private final PasswordHasher passwords;
  private final CloudTokens tokens;
  private final Clock clock;

  public CloudGoogleAccounts(
      CloudDatabase database,
      CloudGoogleIdentityVerifier verifier,
      CloudSessions sessions,
      PasswordHasher passwords,
      CloudTokens tokens,
      Clock clock) {
    this.database = database;
    this.verifier = verifier;
    this.sessions = sessions;
    this.passwords = passwords;
    this.tokens = tokens;
    this.clock = clock;
  }

  public CloudSessions.Tokens login(String idToken, String nonce) {
    var identity = verifier.verify(idToken, nonce);
    String unavailablePassword = passwords.hash(tokens.random());
    return database.transact(
        tx -> {
          var existing =
              tx.one(
                  "SELECT id,bootstrap_used FROM accounts WHERE google_subject = ? AND verified = 1",
                  r -> new String[] {r.getString(1), r.getString(2)},
                  identity.subject());
          UUID owner;
          boolean bootstrap;
          if (existing.isPresent()) {
            owner = UUID.fromString(existing.get()[0]);
            bootstrap = "0".equals(existing.get()[1]);
          } else {
            if (tx.one(
                    "SELECT id FROM accounts WHERE email = ?",
                    r -> r.getString(1),
                    identity.email())
                .isPresent()) throw new CloudFailure(409, "google_link_required");
            owner = UUID.randomUUID();
            bootstrap = true;
            tx.execute(
                "INSERT INTO accounts(id,email,password_hash,name,verified,bootstrap_used,created_at,google_subject) VALUES (?,?,?,?,1,0,?,?)",
                owner,
                identity.email(),
                unavailablePassword,
                identity.name(),
                clock.instant(),
                identity.subject());
            tx.execute(
                "INSERT INTO workspaces(id,owner_id) VALUES (?,?)", UUID.randomUUID(), owner);
          }
          tx.execute(
              "UPDATE accounts SET avatar_url = ? WHERE id = ?", identity.avatarURL(), owner);
          return sessions.create(tx, owner, bootstrap);
        });
  }
}
