package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.ProcessGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Проверяет и исполняет один ранее подготовленный побочный эффект. */
public final class PreparedActionExecutor {
  private final WorkspaceStore store;
  private final Records records;
  private final PermissionService permissions;
  private final GitGateway git;
  private final ProcessGateway processes;
  private final ArtifactStore artifacts;
  private final TokenGenerator tokens;
  private final AgentFiles files;

  public PreparedActionExecutor(
      WorkspaceStore store,
      Records records,
      PermissionService permissions,
      GitGateway git,
      ProcessGateway processes,
      ArtifactStore artifacts,
      TokenGenerator tokens,
      AgentFiles files) {
    this.store = store;
    this.records = records;
    this.permissions = permissions;
    this.git = git;
    this.processes = processes;
    this.artifacts = artifacts;
    this.tokens = tokens;
    this.files = files;
  }

  public Object execute(Entity<AgentSessionData> s, UUID actionId, BooleanSupplier cancelled) {
    var action =
        store.transact(
            tx ->
                Records.require(
                    tx,
                    EntityKind.PREPARED_ACTION,
                    s.ownerId(),
                    actionId,
                    PreparedActionData.class));
    if (!s.id().equals(action.data().sessionId())) throw forbidden();
    if (action.data().status().equals("FINISHED"))
      return store.transact(
          tx ->
              tx
                  .all(
                      EntityKind.TOOL_OPERATION,
                      s.ownerId(),
                      s.projectId(),
                      actionId,
                      ToolOperationData.class)
                  .stream()
                  .filter(op -> op.data().status().equals("FINISHED"))
                  .reduce((first, last) -> last)
                  .orElseThrow(
                      () ->
                          new WorkspaceFailure(
                              409, "operation_unknown", "Нет подтверждённого результата действия"))
                  .data()
                  .result());
    if (action.data().status().equals("DENIED"))
      throw new WorkspaceFailure(403, "permission_denied", "Пользователь запретил действие");
    if (!action.data().status().equals("PREPARED"))
      throw new WorkspaceFailure(409, "operation_unknown", "Сначала сверить исход операции");
    if (!git.inspect(Path.of(s.data().workspace())).baseSha().equals(action.data().baseSha()))
      throw new WorkspaceFailure(409, "action_invalidated", "Исходный коммит изменился");
    if (action.data().capability().equals("patch.apply")) {
      writable(s);
      Path p = files.path(s, required(action.data().arguments(), "path"), true);
      if (!files.hash(p).equals(action.data().arguments().get("beforeHash")))
        throw new WorkspaceFailure(409, "action_invalidated", "Файл изменился после подготовки");
    }
    if (action.data().capability().equals("process.run")
        && !tokens
            .digest(git.snapshot(Path.of(s.data().workspace())))
            .equals(action.data().arguments().get("snapshotHash")))
      throw new WorkspaceFailure(
          409, "action_invalidated", "Рабочие файлы изменились после подготовки команды");
    var operation =
        store.transact(
            tx -> {
              var fresh =
                  Records.require(
                      tx,
                      EntityKind.PREPARED_ACTION,
                      s.ownerId(),
                      actionId,
                      PreparedActionData.class);
              if (!fresh.data().status().equals("PREPARED"))
                throw new WorkspaceFailure(409, "operation_unknown", "Действие уже исполняется");
              if (tx
                  .all(
                      EntityKind.TOOL_OPERATION,
                      s.ownerId(),
                      s.projectId(),
                      null,
                      ToolOperationData.class)
                  .stream()
                  .anyMatch(
                      op ->
                          s.id().equals(op.data().sessionId())
                              && Set.of("UNKNOWN", "RECONCILING", "RUNNING")
                                  .contains(op.data().status())))
                throw new WorkspaceFailure(
                    409, "operation_unknown", "Сначала определите исход незавершённых операций");
              permissions.consume(tx, s.ownerId(), fresh);
              records.change(
                  tx, EntityKind.PREPARED_ACTION, fresh, status(fresh.data(), "EXECUTING"));
              return records.create(
                  tx,
                  EntityKind.TOOL_OPERATION,
                  s.ownerId(),
                  s.projectId(),
                  actionId,
                  new ToolOperationData(
                      s.id(), actionId, action.data().capability(), "RUNNING", null, null));
            });
    try {
      if (cancelled.getAsBoolean())
        throw new WorkspaceFailure(409, "cancelled", "Сессия остановлена");
      Object result;
      if (action.data().capability().equals("patch.apply")) {
        var a = action.data().arguments();
        Path destination = files.path(s, required(a, "path"), true);
        Files.createDirectories(destination.getParent());
        Path temp = Files.createTempFile(destination.getParent(), ".blot-", ".tmp");
        try {
          Files.writeString(temp, required(a, "content"));
          // Проверяем разрешение и исходник ещё раз непосредственно перед заменой файла.
          if (cancelled.getAsBoolean()
              || !store.transact(tx -> permissions.executionAllowed(tx, s.ownerId(), action)))
            throw new WorkspaceFailure(
                403, "permission_revoked", "Разрешение на изменение отозвано");
          Path checked = files.path(s, required(a, "path"), true);
          if (!checked.equals(destination) || !files.hash(checked).equals(a.get("beforeHash")))
            throw new WorkspaceFailure(
                409, "action_invalidated", "Файл изменился после подготовки");
          Files.move(
              temp,
              destination,
              StandardCopyOption.ATOMIC_MOVE,
              StandardCopyOption.REPLACE_EXISTING);
        } finally {
          Files.deleteIfExists(temp);
        }
        result = Map.of("path", a.get("path"), "hash", files.hash(destination));
      } else if (action.data().capability().equals("process.run")) {
        var a = action.data().arguments();
        Object raw = a.get("arguments");
        if (!(raw instanceof List<?> list) || list.stream().anyMatch(v -> !(v instanceof String)))
          throw WorkspaceFailure.invalid("Неверные аргументы процесса");
        int timeout = a.get("timeoutSeconds") instanceof Number n ? n.intValue() : 120;
        var processResult =
            processes.run(
                Path.of(s.data().workspace()),
                Set.of("REVIEWER", "CHECKER", "QA", "SECURITY").contains(s.data().role())
                    ? List.of()
                    : store
                        .transact(
                            tx ->
                                Records.require(
                                    tx,
                                    EntityKind.TASK,
                                    s.ownerId(),
                                    s.data().taskId(),
                                    TaskData.class))
                        .data()
                        .paths(),
                required(a, "program"),
                list.stream().map(String.class::cast).toList(),
                timeout,
                () ->
                    cancelled.getAsBoolean()
                        || !store.transact(
                            tx -> permissions.executionAllowed(tx, s.ownerId(), action)));
        var stored = artifacts.write(processResult.output().getBytes(StandardCharsets.UTF_8));
        var outputArtifact =
            store.transact(
                tx ->
                    records.create(
                        tx,
                        EntityKind.ARTIFACT,
                        s.ownerId(),
                        s.projectId(),
                        s.data().taskId(),
                        new ArtifactData(
                            stored.hash(),
                            "text/plain",
                            stored.relativePath(),
                            action.data().baseSha(),
                            s.id(),
                            s.data().taskId())));
        result =
            Map.of(
                "exitCode",
                processResult.exitCode(),
                "output",
                processResult
                    .output()
                    .substring(0, Math.min(12000, processResult.output().length())),
                "truncated",
                processResult.truncated() || processResult.output().length() > 12000,
                "artifactId",
                outputArtifact.id());
      } else throw forbidden();
      Object value = result;
      store.transact(
          tx -> {
            var op =
                Records.require(
                    tx,
                    EntityKind.TOOL_OPERATION,
                    s.ownerId(),
                    operation.id(),
                    ToolOperationData.class);
            records.change(
                tx,
                EntityKind.TOOL_OPERATION,
                op,
                new ToolOperationData(
                    s.id(), actionId, action.data().capability(), "FINISHED", value, null));
            var fresh =
                Records.require(
                    tx,
                    EntityKind.PREPARED_ACTION,
                    s.ownerId(),
                    actionId,
                    PreparedActionData.class);
            records.change(tx, EntityKind.PREPARED_ACTION, fresh, status(fresh.data(), "FINISHED"));
            return null;
          });
      return result;
    } catch (Exception failure) {
      store.transact(
          tx -> {
            var op =
                Records.require(
                    tx,
                    EntityKind.TOOL_OPERATION,
                    s.ownerId(),
                    operation.id(),
                    ToolOperationData.class);
            records.change(
                tx,
                EntityKind.TOOL_OPERATION,
                op,
                new ToolOperationData(
                    s.id(),
                    actionId,
                    action.data().capability(),
                    "UNKNOWN",
                    null,
                    "operation_interrupted"));
            return null;
          });
      if (failure instanceof WorkspaceFailure f) throw f;
      throw new WorkspaceFailure(503, "tool_failed", "Операция инструмента прервана");
    }
  }

  private static PreparedActionData status(PreparedActionData d, String status) {
    return new PreparedActionData(
        d.capability(), d.sessionId(), d.taskId(), d.baseSha(), d.arguments(), d.hash(), status);
  }

  private static void writable(Entity<AgentSessionData> s) {
    if (!Set.of("BACKEND", "FRONTEND", "BUILDER", "INTEGRATOR").contains(s.data().role()))
      throw forbidden();
  }

  private static WorkspaceFailure forbidden() {
    return new WorkspaceFailure(403, "forbidden", "Инструмент выходит за назначенную область");
  }

  private static String required(Map<String, Object> a, String key) {
    Object value = a.get(key);
    if (!(value instanceof String s)) throw WorkspaceFailure.invalid("Нужно поле " + key);
    return s;
  }
}
