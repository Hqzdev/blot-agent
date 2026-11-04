package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.ports.*;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.automation.AutomationService;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.automation.AutomationData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class AutomationScenarioTest {
  @TempDir Path directory;

  @Test
  void sleepAndRepeatedDeliveryCreateOneRunAndFallBackDoesNotRepeatLocalSlot() {
    var clock = new MutableClock(Instant.parse("2026-10-31T22:00:00Z"));
    var store = new SqliteWorkspaceStore(directory.resolve("data.db"), new JacksonCodec(), clock);
    var records = new Records(clock);
    UUID owner = UUID.randomUUID();
    var actor = new Actor(owner, null, null, true);
    store.transact(
        tx -> {
          tx.insert(
              EntityKind.ACCOUNT,
              new Entity<>(
                  owner,
                  owner,
                  null,
                  null,
                  0,
                  clock.instant(),
                  clock.instant(),
                  new AccountData("owner@example.com", "hash", true, "Owner")));
          return null;
        });
    var project =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.PROJECT,
                    owner,
                    null,
                    null,
                    new ProjectData("Project", directory.toString(), "base", "main", false)));
    var dispatcher = new CommandDispatcher(store, new JacksonCodec(), new TokenGenerator());
    var runs = new RunService(records, new ConversationService(records), new RoleCatalog());
    dispatcher.register(
        "run.create",
        (tx, a, c) -> runs.create(tx, a, c.projectId(), (String) c.payload().get("goal")));
    try (var schedules = new AutomationService(store, records, clock, dispatcher)) {
      var schedule =
          store.transact(
              tx ->
                  schedules.save(
                      tx,
                      actor,
                      project.id(),
                      null,
                      null,
                      new AutomationData(
                          "Daily",
                          "Check sources",
                          "America/New_York",
                          "01:30",
                          List.of(1, 2, 3, 4, 5, 6, 7),
                          null,
                          null,
                          true,
                          100000)));
      assertEquals(Instant.parse("2026-11-01T05:30:00Z"), schedule.data().nextAt());
      clock.now = Instant.parse("2026-11-01T05:35:00Z");
      schedules.tick();
      var advanced =
          store.transact(
              tx ->
                  Records.require(
                      tx, EntityKind.AUTOMATION, owner, schedule.id(), AutomationData.class));
      assertEquals(Instant.parse("2026-11-02T06:30:00Z"), advanced.data().nextAt());
      // Сбой после создания run, но до продвижения времени расписания.
      store.transact(tx -> records.change(tx, EntityKind.AUTOMATION, advanced, schedule.data()));
      schedules.tick();
      assertEquals(
          1,
          store
              .transact(tx -> tx.all(EntityKind.RUN, owner, project.id(), null, RunData.class))
              .size());
      assertEquals(
          1,
          store
              .transact(
                  tx ->
                      tx.all(EntityKind.CHECKPOINT, owner, project.id(), schedule.id(), Map.class))
              .size());
      clock.now = Instant.parse("2026-11-12T12:00:00Z");
      schedules.tick();
      schedules.tick();
      assertEquals(
          2,
          store
              .transact(tx -> tx.all(EntityKind.RUN, owner, project.id(), null, RunData.class))
              .size());
      var events = store.transact(tx -> tx.events(owner, 0, 500));
      assertTrue(
          events.stream()
              .filter(e -> e.type().equals("automation.triggered"))
              .anyMatch(e -> ((Map<?, ?>) e.payload()).get("coalesced").equals(true)));
    }
  }

  private static final class MutableClock extends Clock {
    private Instant now;

    MutableClock(Instant now) {
      this.now = now;
    }

    public Instant instant() {
      return now;
    }

    public ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    public Clock withZone(ZoneId zone) {
      return this;
    }
  }
}
