package dev.blot.application.workspace.commands;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.identity.Actor;
import java.util.*;

/** Все пользовательские изменения проходят один журнал команд. */
public final class CommandDispatcher {
  public record Command(
      int schemaVersion,
      UUID commandId,
      String type,
      UUID projectId,
      Long expectedVersion,
      Map<String, Object> payload) {}

  @FunctionalInterface
  public interface Handler {
    Object execute(WorkspaceStore.Transaction tx, Actor actor, Command command);
  }

  /** Здесь допустимы чтение и проверки внешней системы; побочный эффект остаётся в Handler. */
  @FunctionalInterface
  public interface ReadPreparation {
    Handler prepare(Actor actor, Command command);
  }

  private final WorkspaceStore store;
  private final JsonCodec json;
  private final TokenGenerator tokens;
  private final Map<String, ReadPreparation> handlers =
      new java.util.concurrent.ConcurrentHashMap<>();

  public CommandDispatcher(WorkspaceStore store, JsonCodec json, TokenGenerator tokens) {
    this.store = store;
    this.json = json;
    this.tokens = tokens;
  }

  public void register(String name, Handler handler) {
    registerPrepared(name, (actor, command) -> handler);
  }

  public void registerPrepared(String name, ReadPreparation preparation) {
    if (handlers.putIfAbsent(name, preparation) != null)
      throw new IllegalStateException("Повтор обработчика: " + name);
  }

  public Set<String> types() {
    return Set.copyOf(handlers.keySet());
  }

  public WorkspaceStore.CommandReceipt execute(Actor actor, Command c) {
    if (c.schemaVersion() != 2)
      throw new WorkspaceFailure(409, "schema_incompatible", "Требуется контракт версии 2");
    if (c.commandId() == null || c.type() == null || c.payload() == null)
      throw WorkspaceFailure.invalid("Неверная команда");
    var handler = handlers.get(c.type());
    if (handler == null) throw WorkspaceFailure.invalid("Неизвестная команда");
    String hash = tokens.digest(json.write(c));
    var previous = store.transact(tx -> tx.command(actor.accountId(), c.commandId()));
    if (previous.isPresent()) {
      samePayload(previous.get(), hash);
      return previous.get();
    }
    Handler prepared = handler.prepare(actor, c);
    return store.transact(
        tx -> {
          var old = tx.command(actor.accountId(), c.commandId());
          if (old.isPresent()) {
            samePayload(old.get(), hash);
            return old.get();
          }
          Object result = prepared.execute(tx, actor, c);
          UUID operation = result instanceof Entity<?> e ? e.id() : c.commandId();
          var receipt =
              new WorkspaceStore.CommandReceipt(c.commandId(), hash, "accepted", operation, result);
          tx.command(actor.accountId(), receipt);
          return receipt;
        });
  }

  private void samePayload(WorkspaceStore.CommandReceipt receipt, String hash) {
    if (!receipt.hash().equals(hash))
      throw new WorkspaceFailure(
          409, "duplicate_command_mismatch", "commandId уже использован для другой команды");
  }
}
