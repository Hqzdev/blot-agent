package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/** Неизвестный результат инструмента сверяется с файлами; автоматического повторения нет. */
public final class ToolRecoveryService implements AutoCloseable {
  private final WorkspaceStore store;
  private final Records records;
  private final AgentFiles files;
  private final GitGateway git;
  private final TokenGenerator tokens;
  private final ScheduledExecutorService executor =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-tool-recovery").factory());

  public ToolRecoveryService(
      WorkspaceStore store,
      Records records,
      AgentFiles files,
      GitGateway git,
      TokenGenerator tokens) {
    this.store = store;
    this.records = records;
    this.files = files;
    this.git = git;
    this.tokens = tokens;
  }

  public Object request(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version, boolean abandon) {
    var op =
        Records.require(
            tx, EntityKind.TOOL_OPERATION, actor.accountId(), id, ToolOperationData.class);
    Records.version(op, version);
    if (op.data().name().startsWith("git.") || !op.data().status().equals("UNKNOWN"))
      throw WorkspaceFailure.invalid("Эта операция не ожидает сверки инструмента");
    var d = op.data();
    if (abandon) {
      var result =
          records.change(
              tx,
              EntityKind.TOOL_OPERATION,
              op,
              new ToolOperationData(
                  d.sessionId(),
                  d.preparedActionId(),
                  d.name(),
                  "ABANDONED",
                  null,
                  "abandoned_by_user"));
      records.create(
          tx,
          EntityKind.CHECKPOINT,
          actor.accountId(),
          op.projectId(),
          op.id(),
          Map.of("type", "abandoned_operation", "decidedBy", actor.accountId()));
      return result;
    }
    return records.change(
        tx,
        EntityKind.TOOL_OPERATION,
        op,
        new ToolOperationData(
            d.sessionId(), d.preparedActionId(), d.name(), "RECONCILING", null, null));
  }

  public void start() {
    store.transact(
        tx -> {
          for (var op :
              tx.states(
                  EntityKind.TOOL_OPERATION,
                  ToolOperationData.class,
                  List.of("RUNNING", "RECONCILING"),
                  10000))
            if (!op.data().name().startsWith("git.")) {
              var d = op.data();
              records.change(
                  tx,
                  EntityKind.TOOL_OPERATION,
                  op,
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
    executor.scheduleWithFixedDelay(this::tick, 0, 500, TimeUnit.MILLISECONDS);
  }

  private void tick() {
    try {
      for (var op :
          store.transact(
              tx ->
                  tx.states(
                      EntityKind.TOOL_OPERATION,
                      ToolOperationData.class,
                      List.of("RECONCILING"),
                      100))) if (!op.data().name().startsWith("git.")) reconcile(op);
    } catch (RuntimeException ignored) {
      /* Сохранённое задание остаётся доступным для следующего прохода. */
    }
  }

  private void reconcile(Entity<ToolOperationData> op) {
    String status = "UNKNOWN";
    Object result = null;
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
      var session =
          store.transact(
              tx ->
                  Records.require(
                      tx,
                      EntityKind.AGENT_SESSION,
                      op.ownerId(),
                      op.data().sessionId(),
                      AgentSessionData.class));
      if (action.data().capability().equals("patch.apply")) {
        var args = action.data().arguments();
        String path = (String) args.get("path");
        String hash = files.hash(files.path(session, path, true));
        String after =
            tokens.digest(
                Base64.getEncoder()
                    .encodeToString(
                        ((String) args.get("content")).getBytes(StandardCharsets.UTF_8)));
        if (hash.equals(after)) {
          status = "FINISHED";
          result = Map.of("path", path, "hash", hash);
        } else if (hash.equals(args.get("beforeHash"))) status = "NOT_STARTED";
      } else if (action.data().capability().equals("process.run")
          && tokens
              .digest(git.snapshot(Path.of(session.data().workspace())))
              .equals(action.data().arguments().get("snapshotHash"))) status = "NOT_APPLIED";
    } catch (RuntimeException ignored) {
      /* Несовпадение или недоступность файлов не подтверждают исход. */
    }
    final String outcome = status;
    final Object value = result;
    store.transact(
        tx -> {
          var current =
              Records.require(
                  tx, EntityKind.TOOL_OPERATION, op.ownerId(), op.id(), ToolOperationData.class);
          if (!current.data().status().equals("RECONCILING")) return null;
          var d = current.data();
          records.change(
              tx,
              EntityKind.TOOL_OPERATION,
              current,
              new ToolOperationData(
                  d.sessionId(),
                  d.preparedActionId(),
                  d.name(),
                  outcome,
                  value,
                  outcome.equals("UNKNOWN") ? "recovery_required" : null));
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
                  Set.of("NOT_STARTED", "NOT_APPLIED").contains(outcome) ? "PREPARED" : outcome));
          return null;
        });
  }

  public void close() {
    executor.shutdownNow();
  }
}
