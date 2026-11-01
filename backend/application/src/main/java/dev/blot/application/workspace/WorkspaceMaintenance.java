package dev.blot.application.workspace;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceCleaner;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.projects.WorkspaceCleanupData;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/** Файловая очистка выполняется после фиксации удаления, вне транзакции SQLite. */
public final class WorkspaceMaintenance implements AutoCloseable {
  private final WorkspaceStore store;
  private final WorkspaceCleaner cleaner;
  private final Records records;
  private final ScheduledExecutorService executor =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-workspace-cleanup").factory());

  public WorkspaceMaintenance(WorkspaceStore store, WorkspaceCleaner cleaner, Records records) {
    this.store = store;
    this.cleaner = cleaner;
    this.records = records;
  }

  public void start() {
    // До запуска планировщика в новом JVM прежних подготовок уже нет.
    store.transact(
        tx -> {
          for (var job :
              tx.states(
                  EntityKind.WORKSPACE_CLEANUP,
                  WorkspaceCleanupData.class,
                  List.of("PREPARING"),
                  10000)) tx.delete(EntityKind.WORKSPACE_CLEANUP, job.ownerId(), job.id());
          return null;
        });
    executor.scheduleWithFixedDelay(this::cleanup, 0, 1, TimeUnit.MINUTES);
  }

  public synchronized void cleanup() {
    try {
      var jobs =
          store.transact(
              tx ->
                  tx.states(
                      EntityKind.WORKSPACE_CLEANUP,
                      WorkspaceCleanupData.class,
                      List.of("QUEUED", "RETRY"),
                      1000));
      for (var job : jobs) {
        if (Thread.currentThread().isInterrupted()) return;
        try {
          var data = job.data();
          cleaner.removeRun(Path.of(data.repositoryPath()), data.runId());
          store.transact(
              tx -> {
                tx.delete(EntityKind.WORKSPACE_CLEANUP, job.ownerId(), job.id());
                tx.event(
                    job.ownerId(),
                    null,
                    "workspace.removed",
                    Map.of("projectId", data.projectId(), "runId", data.runId()));
                return null;
              });
        } catch (RuntimeException failure) {
          store.transact(
              tx -> {
                var current =
                    Records.require(
                        tx,
                        EntityKind.WORKSPACE_CLEANUP,
                        job.ownerId(),
                        job.id(),
                        WorkspaceCleanupData.class);
                var data = current.data();
                records.change(
                    tx,
                    EntityKind.WORKSPACE_CLEANUP,
                    current,
                    new WorkspaceCleanupData(
                        data.projectId(),
                        data.runId(),
                        data.repositoryPath(),
                        "RETRY",
                        "Не удалось удалить рабочую область; повторим после восстановления доступа"));
                return null;
              });
        }
      }
    } catch (RuntimeException failure) {
      System.getLogger(WorkspaceMaintenance.class.getName())
          .log(
              System.Logger.Level.WARNING, "Не удалось выполнить очередь очистки рабочих областей");
    }
  }

  public void close() {
    executor.shutdownNow();
  }
}
