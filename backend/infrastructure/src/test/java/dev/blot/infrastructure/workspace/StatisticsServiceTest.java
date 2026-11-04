package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.statistics.StatisticsService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.ReviewData;
import dev.blot.core.workspace.execution.ModelRequestData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import java.nio.file.Path;
import java.time.Clock;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class StatisticsServiceTest {
  @TempDir Path directory;

  @Test
  void usesOwnedUsageAndReportsMissingUsageAndPrice() {
    var clock = Clock.systemUTC();
    var store = new SqliteWorkspaceStore(directory.resolve("data.db"), new JacksonCodec(), clock);
    var records = new Records(clock);
    UUID owner = UUID.randomUUID();
    UUID other = UUID.randomUUID();
    UUID[] projects =
        store.transact(
            tx -> {
              for (UUID account : List.of(owner, other))
                tx.insert(
                    EntityKind.ACCOUNT,
                    new Entity<>(
                        account,
                        account,
                        null,
                        null,
                        0,
                        clock.instant(),
                        clock.instant(),
                        new AccountData(account + "@example.com", "hash", true, "Owner")));
              var own =
                  records.create(
                      tx,
                      EntityKind.PROJECT,
                      owner,
                      null,
                      null,
                      new ProjectData("Own", "/repo", "base", "main", false));
              var foreign =
                  records.create(
                      tx,
                      EntityKind.PROJECT,
                      other,
                      null,
                      null,
                      new ProjectData("Foreign", "/other", "base", "main", false));
              records.create(
                  tx,
                  EntityKind.MODEL_REQUEST,
                  owner,
                  own.id(),
                  null,
                  new ModelRequestData(
                      "Model", "Work", 0, "COMPLETED", null, null, 200L, 50L, null));
              records.create(
                  tx,
                  EntityKind.MODEL_REQUEST,
                  owner,
                  own.id(),
                  null,
                  new ModelRequestData(
                      "Model", "Work", 0, "INTERRUPTED", null, null, null, null, "host_restarted"));
              records.create(
                  tx,
                  EntityKind.MODEL_REQUEST,
                  owner,
                  own.id(),
                  null,
                  new ModelRequestData("Model", "Work", 0, "QUEUED", null, null, null, null, null));
              records.create(
                  tx,
                  EntityKind.MODEL_REQUEST,
                  other,
                  foreign.id(),
                  null,
                  new ModelRequestData(
                      "Model", "Work", 0, "COMPLETED", null, null, 9999L, 9999L, null));
              records.create(
                  tx,
                  EntityKind.RUN,
                  owner,
                  own.id(),
                  null,
                  new RunData("Result", "COMPLETED", null, 1, null));
              records.create(
                  tx,
                  EntityKind.REVIEW,
                  owner,
                  own.id(),
                  null,
                  new ReviewData(
                      null,
                      null,
                      "hash",
                      UUID.randomUUID(),
                      UUID.randomUUID(),
                      "changes_requested",
                      List.of("Fix", "Check")));
              return new UUID[] {own.id(), foreign.id()};
            });
    var service = new StatisticsService(store);
    var actor = new Actor(owner, null, null, true);
    var stats = service.read(actor, projects[0]);
    assertEquals(200L, stats.knownInputTokens());
    assertEquals(50L, stats.knownOutputTokens());
    assertEquals(1L, stats.requestsWithUnknownUsage());
    assertTrue(stats.usageIncomplete());
    assertEquals(1L, stats.queuedRequests());
    assertEquals(0L, stats.activeRequests());
    assertEquals(Map.of("COMPLETED", 1L), stats.runsByStatus());
    assertEquals(1L, stats.reviews());
    assertEquals(2L, stats.findings());
    assertNull(stats.costMinorUnits());
    assertNull(stats.currency());
    assertEquals(stats, service.read(actor, null));
    assertThrows(WorkspaceFailure.class, () -> service.read(actor, projects[1]));
  }
}
