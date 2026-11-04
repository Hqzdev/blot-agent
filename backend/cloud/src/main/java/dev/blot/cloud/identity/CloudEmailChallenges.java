package dev.blot.cloud.identity;

import dev.blot.application.ports.EmailSender;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;
import java.util.function.Function;

public final class CloudEmailChallenges {
  private record Challenge(UUID id, String hash, long expires, int attempts) {}

  private record Result<T>(boolean valid, T value) {}

  private final CloudDatabase database;
  private final CloudTokens tokens;
  private final EmailSender mail;
  private final CloudRateLimiter rates;
  private final Clock clock;

  public CloudEmailChallenges(
      CloudDatabase database,
      CloudTokens tokens,
      EmailSender mail,
      CloudRateLimiter rates,
      Clock clock) {
    this.database = database;
    this.tokens = tokens;
    this.mail = mail;
    this.rates = rates;
    this.clock = clock;
  }

  public void send(UUID owner, String email, String purpose) {
    send(owner, email, purpose, null, null);
  }

  public void allowResetRequest(String email) {
    rates.check("reset-address:" + email, 1, Duration.ofSeconds(60));
  }

  public void send(
      UUID owner, String email, String purpose, String registrationHash, String registrationName) {
    rates.check("email:" + purpose + ":" + owner, 1, Duration.ofSeconds(60));
    UUID id = UUID.randomUUID();
    String code = tokens.code();
    database.transact(
        tx -> {
          tx.execute(
              "DELETE FROM email_challenges WHERE owner_id = ? AND purpose = ?", owner, purpose);
          tx.execute(
              "INSERT INTO email_challenges(id, owner_id, purpose, code_hash, expires, created_at, registration_hash, registration_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              id,
              owner,
              purpose,
              tokens.challengeDigest(id, code),
              clock.instant().plusSeconds(600),
              clock.instant(),
              registrationHash,
              registrationName);
          return null;
        });
    mail.sendCode(email, code, purpose);
  }

  public <T> T consume(
      UUID owner, String purpose, String code, Function<CloudTransaction, T> accepted) {
    if (code == null || !code.matches("[0-9]{6}"))
      throw new CloudFailure(400, "code_expired_or_invalid");
    Result<T> result =
        database.transact(
            tx -> {
              var challenge =
                  tx.one(
                      "SELECT id, code_hash, expires, attempts FROM email_challenges WHERE owner_id = ? AND purpose = ? ORDER BY created_at DESC LIMIT 1",
                      r ->
                          new Challenge(
                              UUID.fromString(r.getString(1)),
                              r.getString(2),
                              r.getLong(3),
                              r.getInt(4)),
                      owner,
                      purpose);
              if (challenge.isEmpty()) return new Result<T>(false, null);
              Challenge value = challenge.get();
              if (value.expires() <= clock.millis() || value.attempts() >= 5)
                return new Result<T>(false, null);
              tx.execute(
                  "UPDATE email_challenges SET attempts = attempts + 1 WHERE id = ?", value.id());
              if (!tokens.equal(value.hash(), tokens.challengeDigest(value.id(), code)))
                return new Result<T>(false, null);
              T output = accepted.apply(tx);
              tx.execute("DELETE FROM email_challenges WHERE id = ?", value.id());
              return new Result<>(true, output);
            });
    if (!result.valid()) throw new CloudFailure(400, "code_expired_or_invalid");
    return result.value();
  }
}
