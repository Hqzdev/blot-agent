package dev.blot.application.workspace.identity;

import dev.blot.application.ports.*;
import dev.blot.application.ports.PasswordHasher;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.identity.AuthSessionData;
import java.time.*;
import java.util.*;

public final class AccountService {
  public record AccountView(UUID id, String email, String displayName, boolean verified) {}

  private final WorkspaceStore store;
  private final PasswordHasher hasher;
  private final EmailChallengeService challenges;
  private final Records records;
  private final Clock clock;

  public AccountService(
      WorkspaceStore store,
      PasswordHasher hasher,
      EmailChallengeService challenges,
      Records records,
      Clock clock) {
    this.store = store;
    this.hasher = hasher;
    this.challenges = challenges;
    this.records = records;
    this.clock = clock;
  }

  public AccountView registerAccount(String email, String password, String name) {
    email = email(email);
    validatePassword(password);
    String hash = hasher.hash(password);
    String address = email;
    var account =
        store.transact(
            tx -> {
              if (find(tx, address).isPresent())
                throw new WorkspaceFailure(409, "email_exists", "Аккаунт уже существует");
              UUID id = UUID.randomUUID();
              var e =
                  new Entity<>(
                      id,
                      id,
                      null,
                      null,
                      0,
                      clock.instant(),
                      clock.instant(),
                      new AccountData(
                          address,
                          hash,
                          false,
                          name == null ? address : Records.text(name, "name", 100)));
              tx.insert(EntityKind.ACCOUNT, e);
              return e;
            });
    challenges.send(account, "verify");
    return view(account);
  }

  public AccountView verifyEmail(String email, String code) {
    var a = account(email);
    challenges.consume(a.id(), "verify", code);
    return store.transact(
        tx -> {
          var fresh = Records.require(tx, EntityKind.ACCOUNT, a.id(), a.id(), AccountData.class);
          var d = fresh.data();
          return view(
              records.change(
                  tx,
                  EntityKind.ACCOUNT,
                  fresh,
                  new AccountData(d.email(), d.passwordHash(), true, d.displayName())));
        });
  }

  public void resend(String email) {
    var a = account(email);
    if (!a.data().verified()) challenges.send(a, "verify");
  }

  public void requestReset(String email) {
    var a = store.transact(tx -> find(tx, email(email)));
    if (a.isPresent()) challenges.send(a.get(), "reset");
  }

  public void reset(String email, String code, String password) {
    validatePassword(password);
    var a = account(email);
    challenges.consume(a.id(), "reset", code);
    String hash = hasher.hash(password);
    store.transact(
        tx -> {
          var fresh = Records.require(tx, EntityKind.ACCOUNT, a.id(), a.id(), AccountData.class);
          var d = fresh.data();
          records.change(
              tx,
              EntityKind.ACCOUNT,
              fresh,
              new AccountData(d.email(), hash, d.verified(), d.displayName()));
          for (var s :
              tx.list(EntityKind.AUTH_SESSION, a.id(), null, null, AuthSessionData.class, 10000))
            tx.delete(EntityKind.AUTH_SESSION, a.id(), s.id());
          return null;
        });
  }

  public Entity<AccountData> credentials(String email, String password) {
    var a = account(email);
    if (password == null
        || password.length() > 128
        || !hasher.matches(password, a.data().passwordHash()))
      throw new WorkspaceFailure(401, "wrong_credentials", "Неверная почта или пароль");
    if (!a.data().verified())
      throw new WorkspaceFailure(403, "email_unverified", "Подтвердите почту");
    return a;
  }

  public AccountView me(Actor actor) {
    return store.transact(
        tx ->
            view(
                Records.require(
                    tx,
                    EntityKind.ACCOUNT,
                    actor.accountId(),
                    actor.accountId(),
                    AccountData.class)));
  }

  private Entity<AccountData> account(String email) {
    return store.transact(
        tx ->
            find(tx, email(email))
                .orElseThrow(
                    () ->
                        new WorkspaceFailure(
                            401, "wrong_credentials", "Неверная почта или пароль")));
  }

  private Optional<Entity<AccountData>> find(WorkspaceStore.Transaction tx, String email) {
    return tx.scan(EntityKind.ACCOUNT, AccountData.class, 10000).stream()
        .filter(a -> a.data().email().equals(email))
        .findFirst();
  }

  private static String email(String value) {
    String e = Records.text(value, "email", 254).toLowerCase(Locale.ROOT);
    if (!e.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+"))
      throw WorkspaceFailure.invalid("Неверная почта");
    return e;
  }

  private static void validatePassword(String p) {
    if (p == null || p.length() < 12 || p.length() > 128)
      throw WorkspaceFailure.invalid("Пароль должен содержать от 12 до 128 символов");
  }

  private static AccountView view(Entity<AccountData> a) {
    return new AccountView(a.id(), a.data().email(), a.data().displayName(), a.data().verified());
  }
}
