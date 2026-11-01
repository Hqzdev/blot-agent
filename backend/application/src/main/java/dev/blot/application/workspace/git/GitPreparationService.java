package dev.blot.application.workspace.git;

import dev.blot.application.ports.*;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.file.Path;
import java.util.*;

/** Чтение remote выполняется до короткой транзакции подготовки разрешения. */
public final class GitPreparationService {
  public record ResolvedRemote(String workspace, String name, GitGateway.Remote value) {}

  private record Source(
      Entity<RunData> run,
      Entity<TaskData> task,
      Entity<ArtifactData> artifact,
      String workspace) {}

  private final WorkspaceStore store;
  private final PermissionService permissions;
  private final GitGateway git;

  public GitPreparationService(
      WorkspaceStore store, PermissionService permissions, GitGateway git) {
    this.store = store;
    this.permissions = permissions;
    this.git = git;
  }

  public ResolvedRemote resolveRemote(Actor actor, UUID runId, String name) {
    Records.text(name, "remote", 200);
    var source = store.transact(tx -> source(tx, actor, runId));
    return new ResolvedRemote(
        source.workspace(), name, git.remote(Path.of(source.workspace()), name));
  }

  public Entity<PreparedActionData> prepare(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID runId,
      String capability,
      Map<String, Object> arguments,
      ResolvedRemote resolved) {
    if (!Set.of("git.commit", "git.push").contains(capability) || arguments == null)
      throw WorkspaceFailure.invalid("Неверная операция Git");
    var source = source(tx, actor, runId);
    var args = new LinkedHashMap<String, Object>(arguments);
    args.put("snapshotHash", source.artifact().data().hash());
    args.put("artifactId", source.artifact().id());
    args.put("workspace", source.workspace());
    args.put("requirementsVersion", source.run().data().requirementsVersion());
    if (capability.equals("git.commit"))
      Records.text((String) args.get("message"), "message", 1000);
    else {
      Records.text((String) args.get("refspec"), "refspec", 500);
      if (resolved == null
          || !resolved.workspace().equals(source.workspace())
          || !resolved.name().equals(args.get("remote")))
        throw WorkspaceFailure.conflict("Исходная рабочая область изменилась");
      var commits =
          tx
              .all(
                  EntityKind.TOOL_OPERATION,
                  actor.accountId(),
                  source.run().projectId(),
                  null,
                  ToolOperationData.class)
              .stream()
              .filter(
                  op ->
                      op.data().name().equals("git.commit")
                          && op.data().status().equals("FINISHED")
                          && op.data().sessionId().equals(source.task().data().authorSessionId()))
              .toList();
      if (commits.isEmpty())
        throw new WorkspaceFailure(409, "gate_not_satisfied", "Сначала выполните принятый commit");
      Object result = commits.getLast().data().result();
      if (!(result instanceof Map<?, ?> map) || !(map.get("result") instanceof String commit))
        throw WorkspaceFailure.invalid("Неизвестен SHA коммита");
      args.put("expectedCommit", commit);
      args.put("pushUrls", resolved.value().pushUrls());
      args.put("defaultBranch", resolved.value().defaultBranch());
    }
    return permissions.prepare(
        tx,
        actor.accountId(),
        source.run().projectId(),
        source.task().data().authorSessionId(),
        source.task().id(),
        capability,
        source.artifact().data().baseSha(),
        args);
  }

  private Source source(WorkspaceStore.Transaction tx, Actor actor, UUID runId) {
    var run = Records.require(tx, EntityKind.RUN, actor.accountId(), runId, RunData.class);
    if (!Set.of("READY_FOR_ACCEPTANCE", "COMPLETED").contains(run.data().status()))
      throw new WorkspaceFailure(
          409, "gate_not_satisfied", "Сначала завершите интеграцию и проверки");
    var marker =
        tx.all(EntityKind.CHECKPOINT, actor.accountId(), run.projectId(), runId, Map.class).stream()
            .filter(
                row ->
                    "integration".equals(row.data().get("phase"))
                        && ((Number) row.data().getOrDefault("revision", 1)).longValue()
                            == run.data().requirementsVersion())
            .findFirst()
            .orElseThrow(WorkspaceFailure::missing);
    var task =
        Records.require(
            tx,
            EntityKind.TASK,
            actor.accountId(),
            UUID.fromString(marker.data().get("taskId").toString()),
            TaskData.class);
    var artifact =
        Records.require(
            tx,
            EntityKind.ARTIFACT,
            actor.accountId(),
            task.data().artifactId(),
            ArtifactData.class);
    var session =
        Records.require(
            tx,
            EntityKind.AGENT_SESSION,
            actor.accountId(),
            task.data().authorSessionId(),
            AgentSessionData.class);
    return new Source(run, task, artifact, session.data().workspace());
  }
}
