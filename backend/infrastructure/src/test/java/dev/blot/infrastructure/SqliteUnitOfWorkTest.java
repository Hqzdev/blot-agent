package dev.blot.infrastructure;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.*;
import dev.blot.application.ApplicationEvent;
import dev.blot.application.ApplicationResult;
import dev.blot.application.BlotApplicationService;
import dev.blot.core.*;
import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.RunStatus;
import dev.blot.infrastructure.database.SqliteUnitOfWork;
import dev.blot.infrastructure.database.StorageException;
import java.nio.file.Path;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SqliteUnitOfWorkTest {
  @TempDir Path directory;

  private static <T> T value(ApplicationResult<T> result) {
    return ((ApplicationResult.Success<T>) result).value();
  }

  @Test
  void roundTripAndDurableOutbox() throws Exception {
    Path file = directory.resolve("blot.db");
    var store = new SqliteUnitOfWork(file);
    var service = new BlotApplicationService(store, Clock.systemUTC(), UUID::randomUUID);
    var project =
        value(service.createProject(new BlotApplicationService.CreateProject("Blot", directory)));
    var run = value(service.createRun(new BlotApplicationService.CreateRun(project.id(), "goal")));
    var revision =
        value(
            service.addSpecificationRevision(
                new BlotApplicationService.AddSpecificationRevision(run.id(), "spec")));
    var first =
        value(
            service.createTask(
                new BlotApplicationService.CreateTask(
                    project.id(), run.id(), "first", List.of("done"), Set.of())));
    var second =
        value(
            service.createTask(
                new BlotApplicationService.CreateTask(
                    project.id(), run.id(), "second", List.of("done"), Set.of(first.id()))));
    var reopened =
        new BlotApplicationService(new SqliteUnitOfWork(file), Clock.systemUTC(), UUID::randomUUID);
    assertEquals(project, value(reopened.getProject(project.id())));
    assertEquals(run, value(reopened.getRun(run.id())));
    assertEquals(List.of(revision), value(reopened.getSpecificationHistory(run.id())));
    assertTrue(value(reopened.getTasks(run.id())).contains(second));
    try (Connection c = DriverManager.getConnection("jdbc:sqlite:" + file);
        Statement s = c.createStatement();
        ResultSet r = s.executeQuery("SELECT count(*), max(seq) FROM outbox")) {
      assertEquals(5, r.getInt(1));
      assertEquals(5, r.getInt(2));
    }
  }

  @Test
  void exceptionRollsBackStateAndEvents() {
    var store = new SqliteUnitOfWork(directory.resolve("rollback.db"));
    UUID id = UUID.randomUUID();
    assertThrows(
        IllegalStateException.class,
        () ->
            store.transact(
                tx -> {
                  tx.projects().save(new Project(id, "project", directory, Instant.now()));
                  tx.appendEvent(
                      new ApplicationEvent(
                          UUID.randomUUID(),
                          id,
                          null,
                          id,
                          1,
                          0,
                          Instant.now(),
                          "project.created",
                          Map.of()));
                  throw new IllegalStateException("rollback");
                }));
    assertTrue(store.transact(tx -> tx.projects().findById(id)).isEmpty());
  }

  @Test
  void schemaRejectsOrphanRun() {
    var store = new SqliteUnitOfWork(directory.resolve("constraints.db"));
    var error =
        assertThrows(
            StorageException.class,
            () ->
                store.transact(
                    tx -> {
                      tx.runs()
                          .save(
                              new Run(
                                  UUID.randomUUID(),
                                  UUID.randomUUID(),
                                  "goal",
                                  Instant.now(),
                                  RunStatus.DRAFT,
                                  0));
                      return null;
                    }));
    assertEquals(StorageException.Kind.CONSTRAINT, error.kind());
  }
}
