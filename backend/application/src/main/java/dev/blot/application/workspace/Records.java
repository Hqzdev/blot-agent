package dev.blot.application.workspace;

import dev.blot.application.ports.WorkspaceStore;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import java.time.Clock;
import java.util.UUID;

/** Создание и изменение записи всегда сопровождаются событием. */
public final class Records {
  private final Clock clock;

  public Records(Clock clock) {
    this.clock = clock;
  }

  public <T> Entity<T> create(
      WorkspaceStore.Transaction tx,
      EntityKind kind,
      UUID owner,
      UUID project,
      UUID parent,
      T data) {
    var e =
        new Entity<>(
            UUID.randomUUID(), owner, project, parent, 0, clock.instant(), clock.instant(), data);
    tx.insert(kind, e);
    tx.event(
        owner,
        project,
        kind.name().toLowerCase() + ".created",
        java.util.Map.of("id", e.id(), "version", e.version()));
    return e;
  }

  public <T> Entity<T> change(WorkspaceStore.Transaction tx, EntityKind kind, Entity<T> e, T data) {
    var next = e.change(data, clock.instant());
    tx.update(kind, next, e.version());
    tx.event(
        e.ownerId(),
        e.projectId(),
        kind.name().toLowerCase() + ".updated",
        java.util.Map.of("id", e.id(), "version", next.version()));
    return next;
  }

  public static <T> Entity<T> require(
      WorkspaceStore.Transaction tx, EntityKind kind, UUID owner, UUID id, Class<T> type) {
    return tx.find(kind, owner, id, type).orElseThrow(WorkspaceFailure::missing);
  }

  public static void version(Entity<?> e, Long expected) {
    if (expected == null || e.version() != expected)
      throw WorkspaceFailure.conflict("Нужна актуальная версия записи");
  }

  public static String text(String value, String field, int max) {
    if (value == null || value.isBlank() || value.length() > max)
      throw WorkspaceFailure.invalid("Неверное поле: " + field);
    return value.strip();
  }
}
