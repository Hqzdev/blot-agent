package dev.blot.application.workspace.git;

import dev.blot.application.ports.*;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.identity.GrantData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/** Побочный эффект выполняется после сохранения задания, вне транзакции SQLite. */
public final class GitOperationService implements AutoCloseable {
  private final WorkspaceStore store;
  private final Records records;
  private final PermissionService permissions;
  private final GitGateway git;
  private final TokenGenerator tokens;
  private final ScheduledExecutorService executor =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-git-operations").factory());

  public GitOperationService(
      WorkspaceStore store,
      Records records,
      PermissionService permissions,
      GitGateway git,
      TokenGenerator tokens) {
    this.store = store;
    this.records = records;
    this.permissions = permissions;
    this.git = git;
    this.tokens = tokens;
  }

  public Entity<ToolOperationData> execute(
      WorkspaceStore.Transaction tx, Actor actor, UUID actionId, Long version) {
    var action =
        Records.require(
            tx, EntityKind.PREPARED_ACTION, actor.accountId(), actionId, PreparedActionData.class);
    Records.version(action, version);
    if (!action.data().capability().startsWith("git.")
        || !action.data().status().equals("PREPARED"))
      throw WorkspaceFailure.invalid("Действие уже принято или недоступно");
    validateAcceptedResult(tx, actor.accountId(), action.data());
    permissions.consume(tx, actor.accountId(), action);
    var a = action.data();
    records.change(
        tx,
        EntityKind.PREPARED_ACTION,
        action,
        new PreparedActionData(
            a.capability(),
            a.sessionId(),
            a.taskId(),
            a.baseSha(),
            a.arguments(),
            a.hash(),
            "QUEUED"));
    return records.create(
        tx,
        EntityKind.TOOL_OPERATION,
        actor.accountId(),
        action.projectId(),
        actionId,
        new ToolOperationData(a.sessionId(), actionId, a.capability(), "QUEUED", null, null));
  }

  public void start() {
    recover();
    executor.scheduleWithFixedDelay(this::tick, 0, 300, TimeUnit.MILLISECONDS);
  }

  private void tick() {
    try {
      var next =
          store.transact(
              tx ->
                  tx
                      .states(
                          EntityKind.TOOL_OPERATION,
                          ToolOperationData.class,
                          List.of("QUEUED", "RECONCILING", "RUNNING"),
                          10000)
                      .stream()
                      .filter(
                          e ->
                              Set.of("QUEUED", "RECONCILING").contains(e.data().status())
                                  && e.data().name().startsWith("git."))
                      .findFirst());
      next.ifPresent(
          op -> {
            if (op.data().status().equals("RECONCILING")) reconcileOutsideTransaction(op);
            else perform(op);
          });
    } catch (RuntimeException e) {
      /* Ошибка конкретной операции остаётся в её записи. */
    }
  }

  private void validateAcceptedResult(
      WorkspaceStore.Transaction tx, UUID owner, PreparedActionData action) {
    var session =
        Records.require(
            tx, EntityKind.AGENT_SESSION, owner, action.sessionId(), AgentSessionData.class);
    var run = Records.require(tx, EntityKind.RUN, owner, session.parentId(), RunData.class);
    var task = Records.require(tx, EntityKind.TASK, owner, action.taskId(), TaskData.class);
    if (!Set.of("READY_FOR_ACCEPTANCE", "COMPLETED").contains(run.data().status())
        || task.data().revision() != run.data().requirementsVersion())
      throw new WorkspaceFailure(
          409, "action_invalidated", "Требования или состояние запуска изменились");
    var artifact =
        Records.require(
            tx, EntityKind.ARTIFACT, owner, task.data().artifactId(), ArtifactData.class);
    if (!artifact.data().hash().equals(action.arguments().get("snapshotHash")))
      throw new WorkspaceFailure(409, "action_invalidated", "Принятый результат изменился");
  }

  private void perform(Entity<ToolOperationData> operation) {
    try {
      var action =
          store.transact(
              tx -> {
                var op =
                    Records.require(
                        tx,
                        EntityKind.TOOL_OPERATION,
                        operation.ownerId(),
                        operation.id(),
                        ToolOperationData.class);
                var d = op.data();
                if (!d.status().equals("QUEUED"))
                  throw WorkspaceFailure.conflict("Операция уже начата");
                var a =
                    Records.require(
                        tx,
                        EntityKind.PREPARED_ACTION,
                        operation.ownerId(),
                        d.preparedActionId(),
                        PreparedActionData.class);
                validateAcceptedResult(tx, operation.ownerId(), a.data());
                boolean valid =
                    tx
                        .list(
                            EntityKind.GRANT,
                            operation.ownerId(),
                            null,
                            a.id(),
                            GrantData.class,
                            10000)
                        .stream()
                        .anyMatch(
                            g ->
                                !g.data().revoked()
                                    && g.data().expiresAt().isAfter(java.time.Instant.now())
                                    && g.data().actionHash().equals(a.data().hash()));
                if (!valid)
                  throw new WorkspaceFailure(
                      403, "permission_required", "Разрешение отозвано или истекло");
                records.change(
                    tx,
                    EntityKind.TOOL_OPERATION,
                    op,
                    new ToolOperationData(
                        d.sessionId(), d.preparedActionId(), d.name(), "RUNNING", null, null));
                return a;
              });
      var d = action.data();
      Path workspace = Path.of((String) d.arguments().get("workspace"));
      String result;
      if (d.capability().equals("git.commit")) {
        if (!tokens.digest(git.snapshot(workspace)).equals(d.arguments().get("snapshotHash")))
          throw new WorkspaceFailure(
              409, "action_invalidated", "Изменения не совпадают с принятым результатом");
        result =
            git.commit(
                workspace,
                d.baseSha(),
                (String) d.arguments().get("snapshotHash"),
                (String) d.arguments().get("message")
                    + "\n\n[blot-operation:"
                    + operation.id()
                    + "]");
      } else {
        var current = git.inspect(workspace);
        if (!current.baseSha().equals(d.arguments().get("expectedCommit")) || current.dirty())
          throw new WorkspaceFailure(
              409, "action_invalidated", "Принятый коммит или рабочие файлы изменились");
        var remote = git.remote(workspace, (String) d.arguments().get("remote"));
        if (!remote.pushUrls().equals(d.arguments().get("pushUrls"))
            || !remote.defaultBranch().equals(d.arguments().get("defaultBranch")))
          throw new WorkspaceFailure(409, "action_invalidated", "Адрес remote изменился");
        result =
            git.push(
                workspace,
                (String) d.arguments().get("remote"),
                (String) d.arguments().get("refspec"),
                (String) d.arguments().get("expectedCommit"));
      }
      complete(operation, "FINISHED", Map.of("result", result), null);
    } catch (WorkspaceFailure failure) {
      complete(operation, "UNKNOWN", null, failure.code());
    } catch (RuntimeException failure) {
      complete(operation, "UNKNOWN", null, "operation_interrupted");
    }
  }

  private void complete(Entity<ToolOperationData> op, String status, Object result, String error) {
    store.transact(
        tx -> {
          var current =
              Records.require(
                  tx, EntityKind.TOOL_OPERATION, op.ownerId(), op.id(), ToolOperationData.class);
          var d = current.data();
          records.change(
              tx,
              EntityKind.TOOL_OPERATION,
              current,
              new ToolOperationData(
                  d.sessionId(), d.preparedActionId(), d.name(), status, result, error));
          var action =
              Records.require(
                  tx,
                  EntityKind.PREPARED_ACTION,
                  op.ownerId(),
                  d.preparedActionId(),
                  PreparedActionData.class);
          var a = action.data();
          records.change(
              tx,
              EntityKind.PREPARED_ACTION,
              action,
              new PreparedActionData(
                  a.capability(),
                  a.sessionId(),
                  a.taskId(),
                  a.baseSha(),
                  a.arguments(),
                  a.hash(),
                  status.equals("NOT_STARTED") ? "PREPARED" : status));
          return null;
        });
  }

  public Object reconcile(WorkspaceStore.Transaction tx, Actor actor, UUID id) {
    var op =
        Records.require(
            tx, EntityKind.TOOL_OPERATION, actor.accountId(), id, ToolOperationData.class);
    if (!op.data().status().equals("UNKNOWN")) return op;
    var d = op.data();
    return records.change(
        tx,
        EntityKind.TOOL_OPERATION,
        op,
        new ToolOperationData(
            d.sessionId(), d.preparedActionId(), d.name(), "RECONCILING", null, null));
  }

  private void reconcileOutsideTransaction(Entity<ToolOperationData> op) {
    try {
      var action =
          store.transact(
              tx ->
                  Records.require(
                      tx,
                      EntityKind.PREPARED_ACTION,
                      op.ownerId(),
                      op.data().preparedActionId(),
                      PreparedActionData.class));
      Path workspace = Path.of((String) action.data().arguments().get("workspace"));
      var state = git.inspect(workspace);
      String status = "UNKNOWN";
      String result = null;
      if (op.data().name().equals("git.commit")) {
        if (state.baseSha().equals(action.data().baseSha())) status = "NOT_STARTED";
        else if (action.data().baseSha().equals(state.parentSha())
            && state.message() != null
            && state.message().contains("[blot-operation:" + op.id() + "]")) {
          status = "FINISHED";
          result = state.baseSha();
        }
      } else if (op.data().name().equals("git.push")) {
        String refspec = (String) action.data().arguments().get("refspec");
        String destination = refspec.substring(refspec.indexOf(':') + 1);
        var info = git.remote(workspace, (String) action.data().arguments().get("remote"));
        if (!info.pushUrls().equals(action.data().arguments().get("pushUrls")))
          throw WorkspaceFailure.conflict("Remote изменился после подготовки");
        String actual =
            git.remoteHead(
                workspace, (String) action.data().arguments().get("remote"), destination);
        if (actual.startsWith(action.data().arguments().get("expectedCommit") + "\t")) {
          status = "FINISHED";
          result = actual;
        }
      }
      complete(
          op,
          status,
          result == null ? null : Map.of("result", result),
          status.equals("UNKNOWN") ? "recovery_required" : null);
    } catch (RuntimeException failure) {
      complete(op, "UNKNOWN", null, "recovery_required");
    }
  }

  private void recover() {
    store.transact(
        tx -> {
          for (var e :
              tx.states(
                  EntityKind.TOOL_OPERATION,
                  ToolOperationData.class,
                  List.of("QUEUED", "RECONCILING", "RUNNING"),
                  10000))
            if (e.data().name().startsWith("git.")
                && Set.of("RUNNING", "RECONCILING").contains(e.data().status())) {
              var d = e.data();
              records.change(
                  tx,
                  EntityKind.TOOL_OPERATION,
                  e,
                  new ToolOperationData(
                      d.sessionId(),
                      d.preparedActionId(),
                      d.name(),
                      "UNKNOWN",
                      null,
                      "host_restarted"));
            }
          return null;
        });
  }

  public void close() {
    executor.shutdownNow();
  }
}
