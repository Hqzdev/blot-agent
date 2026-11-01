package dev.blot.application.workspace.agent;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.WorkspacePaths;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

public final class DelegationService {
  private final WorkspaceStore store;
  private final Records records;

  public DelegationService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public Entity<TaskData> spawn(
      Entity<AgentSessionData> parent,
      String title,
      List<String> criteria,
      String role,
      List<String> paths) {
    if (parent.data().depth() != 0 || !Set.of("SCOUT", "BUILDER", "CHECKER").contains(role))
      throw new WorkspaceFailure(
          403, "delegation_forbidden", "Mote не может создавать других Motes");
    if (role.equals("BUILDER")
        && !Set.of("BACKEND", "FRONTEND", "INTEGRATOR").contains(parent.data().role()))
      throw new WorkspaceFailure(
          403, "delegation_forbidden", "Родитель не может делегировать изменение кода");
    if (role.equals("CHECKER")
        && !Set.of("BACKEND", "FRONTEND", "INTEGRATOR").contains(parent.data().role()))
      throw new WorkspaceFailure(
          403, "delegation_forbidden", "Родитель не может делегировать запуск проверок");
    return store.transact(
        tx -> {
          var run =
              Records.require(
                  tx, EntityKind.RUN, parent.ownerId(), parent.parentId(), RunData.class);
          if (!run.data().status().equals("RUNNING"))
            throw WorkspaceFailure.invalid("Запуск остановлен");
          var source =
              Records.require(
                  tx, EntityKind.TASK, parent.ownerId(), parent.data().taskId(), TaskData.class);
          if (paths == null
              || paths.isEmpty()
              || paths.stream()
                  .anyMatch(
                      p ->
                          !WorkspacePaths.isSafeRelative(p)
                              || source.data().paths().stream()
                                  .noneMatch(
                                      scope ->
                                          scope.equals(".")
                                              || p.equals(scope)
                                              || p.startsWith(scope + "/"))))
            throw new WorkspaceFailure(
                403, "scope_violation", "Область Mote превышает область родителя");
          if (criteria == null || criteria.isEmpty())
            throw WorkspaceFailure.invalid("Нужны критерии Mote");
          String goal = Records.text(title, "title", 1000);
          var children =
              tx
                  .list(
                      EntityKind.TASK,
                      parent.ownerId(),
                      parent.projectId(),
                      parent.parentId(),
                      TaskData.class,
                      10000)
                  .stream()
                  .filter(t -> parent.id().equals(t.data().parentSessionId()))
                  .toList();
          var existing =
              children.stream()
                  .filter(t -> t.data().title().equals(goal) && t.data().role().equals(role))
                  .findFirst();
          if (existing.isPresent()) return existing.get();
          if (children.size() >= 4)
            throw new WorkspaceFailure(429, "mote_limit", "Достигнут лимит дочерних задач");
          return records.create(
              tx,
              EntityKind.TASK,
              parent.ownerId(),
              parent.projectId(),
              parent.parentId(),
              new TaskData(
                      goal,
                      List.copyOf(criteria),
                      List.of(),
                      role,
                      List.copyOf(paths),
                      "READY",
                      null,
                      null,
                      parent.id())
                  .atRevision(source.data().revision()));
        });
  }

  public Object results(Entity<AgentSessionData> parent) {
    var children =
        store
            .transact(
                tx ->
                    tx.list(
                        EntityKind.TASK,
                        parent.ownerId(),
                        parent.projectId(),
                        parent.parentId(),
                        TaskData.class,
                        10000))
            .stream()
            .filter(t -> parent.id().equals(t.data().parentSessionId()))
            .toList();
    if (children.stream()
        .anyMatch(t -> !Set.of("ACCEPTED", "FAILED", "CANCELLED").contains(t.data().status())))
      throw new WorkspaceFailure(409, "child_wait", "Ожидание результатов Motes");
    return children;
  }
}
