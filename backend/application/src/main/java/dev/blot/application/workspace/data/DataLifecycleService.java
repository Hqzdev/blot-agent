package dev.blot.application.workspace.data;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.WorkspaceCleanupData;
import java.util.*;

public final class DataLifecycleService {
  private static final Set<EntityKind> PRIVATE =
      Set.of(EntityKind.ACCOUNT, EntityKind.CHALLENGE, EntityKind.AUTH_SESSION, EntityKind.PAIRING);
  private final WorkspaceStore store;
  private final Records records;

  public DataLifecycleService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public Map<String, Object> exportProject(Actor actor, UUID project) {
    return store.transact(
        tx -> {
          Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
          var result = new LinkedHashMap<String, Object>();
          result.put("schemaVersion", 2);
          result.put(
              "project",
              Records.require(
                  tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class));
          for (var kind : EntityKind.values())
            if (!PRIVATE.contains(kind) && kind != EntityKind.PROJECT)
              result.put(kind.name(), tx.all(kind, actor.accountId(), project, null, Object.class));
          return result;
        });
  }

  public Map<String, Object> diagnostics(Actor actor) {
    return store.transact(
        tx -> {
          var records = new LinkedHashMap<String, Object>();
          for (var kind : List.of(EntityKind.RUN, EntityKind.GENERATION, EntityKind.TOOL_OPERATION))
            records.put(
                kind.name(),
                tx.list(kind, actor.accountId(), null, null, Object.class, 10000).stream()
                    .map(
                        e ->
                            Map.of(
                                "id", e.id(), "version", e.version(), "updatedAt", e.updatedAt()))
                    .toList());
          return Map.of(
              "schemaVersion",
              2,
              "watermark",
              Long.toString(tx.watermark(actor.accountId())),
              "records",
              records);
        });
  }

  public void deleteProject(WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var project = Records.require(tx, EntityKind.PROJECT, actor.accountId(), id, ProjectData.class);
    Records.version(project, version);
    var runs = tx.all(EntityKind.RUN, actor.accountId(), id, null, RunData.class);
    var active =
        runs.stream()
            .anyMatch(e -> !Set.of("COMPLETED", "CANCELLED", "FAILED").contains(e.data().status()));
    boolean activeGeneration =
        tx.all(EntityKind.GENERATION, actor.accountId(), id, null, GenerationData.class).stream()
            .anyMatch(g -> Set.of("QUEUED", "RUNNING").contains(g.data().status()));
    if (active || activeGeneration)
      throw new WorkspaceFailure(409, "project_active", "Сначала остановите активные запуски");
    if (tx
        .all(EntityKind.WORKSPACE_CLEANUP, actor.accountId(), id, null, WorkspaceCleanupData.class)
        .stream()
        .anyMatch(e -> e.data().status().equals("PREPARING")))
      throw new WorkspaceFailure(
          409, "project_active", "Дождитесь окончания подготовки рабочей области");
    boolean unknown =
        tx
            .all(EntityKind.TOOL_OPERATION, actor.accountId(), id, null, ToolOperationData.class)
            .stream()
            .anyMatch(
                e ->
                    Set.of("RUNNING", "QUEUED", "UNKNOWN", "RECONCILING")
                        .contains(e.data().status()));
    if (unknown)
      throw new WorkspaceFailure(
          409, "operation_unknown", "Сначала определите исход незавершённых операций");
    for (var run : runs)
      records.create(
          tx,
          EntityKind.WORKSPACE_CLEANUP,
          actor.accountId(),
          null,
          null,
          new WorkspaceCleanupData(id, run.id(), project.data().repositoryPath(), "QUEUED", null));
    for (var kind : EntityKind.values())
      if (kind != EntityKind.PROJECT && !PRIVATE.contains(kind))
        for (var e : tx.all(kind, actor.accountId(), id, null, Object.class))
          tx.delete(kind, actor.accountId(), e.id());
    tx.delete(EntityKind.PROJECT, actor.accountId(), id);
    tx.event(actor.accountId(), null, "project.deleted", Map.of("id", id));
  }
}
