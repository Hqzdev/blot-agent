package dev.blot.application.workspace.identity;

import dev.blot.application.ports.*;
import dev.blot.application.ports.EmailSender;
import dev.blot.application.ports.PasswordHasher;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.ChallengeData;
import java.time.*;
import java.util.*;

public final class EmailChallengeService {
  private final WorkspaceStore store;
  private final EmailSender mail;
  private final PasswordHasher hasher;
  private final Clock clock;
  private final Records records;
  private final TokenGenerator tokens;

  public EmailChallengeService(
      WorkspaceStore store,
      EmailSender mail,
      PasswordHasher hasher,
      Clock clock,
      Records records,
      TokenGenerator tokens) {
    this.store = store;
    this.mail = mail;
    this.hasher = hasher;
    this.clock = clock;
    this.records = records;
    this.tokens = tokens;
  }

  public void send(Entity<AccountData> account, String purpose) {
    String code = tokens.code();
    String hash = hasher.hash(code);
    store.transact(
        tx -> {
          var existing =
              tx
                  .list(EntityKind.CHALLENGE, account.id(), null, null, ChallengeData.class, 10000)
                  .stream()
                  .filter(e -> e.data().purpose().equals(purpose))
                  .toList();
          if (existing.stream()
              .anyMatch(e -> !e.data().used() && e.data().resendAt().isAfter(clock.instant())))
            throw new WorkspaceFailure(429, "rate_limited", "Повторите отправку позже");
          for (var e : existing) tx.delete(EntityKind.CHALLENGE, account.id(), e.id());
          records.create(
              tx,
              EntityKind.CHALLENGE,
              account.id(),
              null,
              null,
              new ChallengeData(
                  account.id(),
                  purpose,
                  hash,
                  clock.instant().plusSeconds(600),
                  clock.instant().plusSeconds(60),
                  0,
                  false));
          return null;
        });
    // Письмо отправляется после commit. Сбой не подтверждает аккаунт.
    mail.sendCode(account.data().email(), code, purpose);
  }

  public void consume(UUID accountId, String purpose, String code) {
    boolean valid =
        store.transact(
            tx -> {
              var entry =
                  tx
                      .list(EntityKind.CHALLENGE, accountId, null, null, ChallengeData.class, 10000)
                      .stream()
                      .filter(e -> e.data().purpose().equals(purpose) && !e.data().used())
                      .findFirst()
                      .orElseThrow(() -> WorkspaceFailure.invalid("Код не найден"));
              var c = entry.data();
              if (!c.expiresAt().isAfter(clock.instant()) || c.attempts() >= 5)
                throw WorkspaceFailure.invalid("Код истёк или исчерпаны попытки");
              boolean correct =
                  code != null && code.matches("[0-9]{6}") && hasher.matches(code, c.codeHash());
              records.change(
                  tx,
                  EntityKind.CHALLENGE,
                  entry,
                  new ChallengeData(
                      accountId,
                      purpose,
                      c.codeHash(),
                      c.expiresAt(),
                      c.resendAt(),
                      c.attempts() + 1,
                      correct));
              return correct;
            });
    // Ошибка возвращается после commit, чтобы неверная попытка не откатилась.
    if (!valid) throw WorkspaceFailure.invalid("Неверный код");
  }
}
