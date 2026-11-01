package dev.blot.application.workspace.artifact;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.WorkspaceStore;
import java.time.*;
import java.util.concurrent.*;

/** Удаляет только старые blobs без ссылок, сохраняя результаты других проектов. */
public final class ArtifactMaintenance implements AutoCloseable {
  private final WorkspaceStore store;
  private final ArtifactStore artifacts;
  private final Clock clock;
  private final ScheduledExecutorService executor =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-artifact-cleanup").factory());

  public ArtifactMaintenance(WorkspaceStore store, ArtifactStore artifacts, Clock clock) {
    this.store = store;
    this.artifacts = artifacts;
    this.clock = clock;
  }

  public void start() {
    executor.scheduleWithFixedDelay(this::cleanup, 1, 1, TimeUnit.HOURS);
  }

  public void cleanup() {
    try {
      var referenced = store.transact(WorkspaceStore.Transaction::referencedArtifacts);
      artifacts.removeUnused(referenced, clock.instant().minus(Duration.ofDays(1)));
    } catch (RuntimeException failure) {
      System.getLogger(ArtifactMaintenance.class.getName())
          .log(System.Logger.Level.WARNING, "Не удалось очистить неиспользуемые артефакты");
    }
  }

  public void close() {
    executor.shutdownNow();
  }
}
