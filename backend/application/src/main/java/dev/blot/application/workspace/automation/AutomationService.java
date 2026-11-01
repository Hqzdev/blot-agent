package dev.blot.application.workspace.automation;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.automation.AutomationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;

public final class AutomationService implements AutoCloseable {
  private final WorkspaceStore store;
  private final Records records;
  private final Clock clock;
  private final CommandDispatcher commands;
  private final ScheduledExecutorService executor =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-schedules").factory());

  public AutomationService(
      WorkspaceStore store, Records records, Clock clock, CommandDispatcher commands) {
    this.store = store;
    this.records = records;
    this.clock = clock;
    this.commands = commands;
  }

  public Entity<AutomationData> save(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID project,
      UUID id,
      Long version,
      AutomationData data) {
    Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    Records.text(data.name(), "name", 200);
    Records.text(data.goal(), "goal", 32000);
    if (data.weekdays() == null
        || data.weekdays().isEmpty()
        || data.weekdays().stream().anyMatch(d -> d < 1 || d > 7)
        || data.tokenBudget() < 8192)
      throw WorkspaceFailure.invalid("Неверное расписание или бюджет");
    Instant next;
    try {
      next = next(data, clock.instant());
    } catch (DateTimeException failure) {
      throw WorkspaceFailure.invalid("Неверное время или часовой пояс расписания");
    }
    var value =
        new AutomationData(
            data.name(),
            data.goal(),
            data.timezone(),
            data.localTime(),
            List.copyOf(data.weekdays()),
            next,
            null,
            data.enabled(),
            data.tokenBudget());
    if (id == null)
      return records.create(tx, EntityKind.AUTOMATION, actor.accountId(), project, null, value);
    var old =
        Records.require(tx, EntityKind.AUTOMATION, actor.accountId(), id, AutomationData.class);
    Records.version(old, version);
    return records.change(tx, EntityKind.AUTOMATION, old, value);
  }

  public void start() {
    executor.scheduleWithFixedDelay(this::tick, 0, 15, TimeUnit.SECONDS);
  }

  public Entity<RunData> runNow(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version, RunService runs) {
    var automation =
        Records.require(tx, EntityKind.AUTOMATION, actor.accountId(), id, AutomationData.class);
    Records.version(automation, version);
    var data = automation.data();
    var run = runs.create(tx, actor, automation.projectId(), data.goal(), data.tokenBudget());
    records.create(
        tx,
        EntityKind.CHECKPOINT,
        actor.accountId(),
        automation.projectId(),
        id,
        Map.of(
            "phase",
            "automation_run",
            "runId",
            run.id(),
            "startedAt",
            clock.instant(),
            "manual",
            true));
    return run;
  }

  public void tick() {
    var due =
        store.transact(tx -> tx.scan(EntityKind.AUTOMATION, AutomationData.class, 10000)).stream()
            .filter(e -> e.data().enabled() && !e.data().nextAt().isAfter(clock.instant()))
            .toList();
    for (var automation : due) {
      var d = automation.data();
      UUID commandId =
          UUID.nameUUIDFromBytes(
              (automation.id() + ":" + d.nextAt())
                  .getBytes(java.nio.charset.StandardCharsets.UTF_8));
      try {
        var receipt =
            commands.execute(
                new Actor(automation.ownerId(), null, null, true),
                new CommandDispatcher.Command(
                    2,
                    commandId,
                    "run.create",
                    automation.projectId(),
                    null,
                    Map.of("goal", d.goal(), "tokenBudget", d.tokenBudget())));
        store.transact(
            tx -> {
              var current =
                  Records.require(
                      tx,
                      EntityKind.AUTOMATION,
                      automation.ownerId(),
                      automation.id(),
                      AutomationData.class);
              if (!current.data().nextAt().equals(d.nextAt())) return null;
              // Квитанция run.create переживает сбой; история не дублируется при её повторе.
              boolean recorded =
                  tx
                      .all(
                          EntityKind.CHECKPOINT,
                          automation.ownerId(),
                          automation.projectId(),
                          automation.id(),
                          Map.class)
                      .stream()
                      .anyMatch(row -> commandId.toString().equals(row.data().get("commandId")));
              if (!recorded)
                records.create(
                    tx,
                    EntityKind.CHECKPOINT,
                    automation.ownerId(),
                    automation.projectId(),
                    automation.id(),
                    Map.of(
                        "phase",
                        "automation_run",
                        "runId",
                        receipt.operationId(),
                        "commandId",
                        commandId.toString(),
                        "startedAt",
                        clock.instant(),
                        "scheduledAt",
                        d.nextAt(),
                        "manual",
                        false,
                        "coalesced",
                        !next(d, d.nextAt()).isAfter(clock.instant())));
              records.change(
                  tx,
                  EntityKind.AUTOMATION,
                  current,
                  new AutomationData(
                      d.name(),
                      d.goal(),
                      d.timezone(),
                      d.localTime(),
                      d.weekdays(),
                      next(d, clock.instant()),
                      d.nextAt(),
                      d.enabled(),
                      d.tokenBudget()));
              tx.event(
                  automation.ownerId(),
                  automation.projectId(),
                  "automation.triggered",
                  Map.of(
                      "id",
                      automation.id(),
                      "scheduledAt",
                      d.nextAt(),
                      "startedAt",
                      clock.instant(),
                      "commandId",
                      commandId,
                      "coalesced",
                      !next(d, d.nextAt()).isAfter(clock.instant())));
              return null;
            });
      } catch (WorkspaceFailure failure) {
        store.transact(
            tx -> {
              var current =
                  Records.require(
                      tx,
                      EntityKind.AUTOMATION,
                      automation.ownerId(),
                      automation.id(),
                      AutomationData.class);
              if (!current.data().nextAt().equals(d.nextAt())) return null;
              records.create(
                  tx,
                  EntityKind.CHECKPOINT,
                  automation.ownerId(),
                  automation.projectId(),
                  automation.id(),
                  Map.of(
                      "phase",
                      "automation_run",
                      "commandId",
                      commandId.toString(),
                      "scheduledAt",
                      d.nextAt(),
                      "startedAt",
                      clock.instant(),
                      "error",
                      failure.code(),
                      "manual",
                      false));
              records.change(
                  tx,
                  EntityKind.AUTOMATION,
                  current,
                  new AutomationData(
                      d.name(),
                      d.goal(),
                      d.timezone(),
                      d.localTime(),
                      d.weekdays(),
                      next(d, clock.instant()),
                      d.nextAt(),
                      false,
                      d.tokenBudget()));
              tx.event(
                  automation.ownerId(),
                  automation.projectId(),
                  "automation.failed",
                  Map.of("id", automation.id(), "code", failure.code()));
              return null;
            });
      }
    }
  }

  static Instant next(AutomationData data, Instant after) {
    ZoneId zone = ZoneId.of(data.timezone());
    LocalTime time = LocalTime.parse(data.localTime());
    LocalDate date = after.atZone(zone).toLocalDate();
    for (int i = 0; i < 8; i++) {
      LocalDate candidate = date.plusDays(i);
      Instant at = candidate.atTime(time).atZone(zone).toInstant();
      if (data.weekdays().contains(candidate.getDayOfWeek().getValue()) && at.isAfter(after))
        return at;
    }
    throw WorkspaceFailure.invalid("Не удалось вычислить следующее срабатывание");
  }

  public void close() {
    executor.shutdownNow();
  }
}
