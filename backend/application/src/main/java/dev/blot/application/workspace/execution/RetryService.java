package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

/** Повтор создаёт новое назначение; неизвестные побочные эффекты сначала требуют сверки. */
public final class RetryService {
  private final Records records;
  private final ConversationService conversations;

  public RetryService(Records records, ConversationService conversations) {
    this.records = records;
    this.conversations = conversations;
  }

  public Entity<TaskData> retryTask(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var task = Records.require(tx, EntityKind.TASK, actor.accountId(), id, TaskData.class);
    Records.version(task, version);
    var d = task.data();
    var run =
        Records.require(tx, EntityKind.RUN, actor.accountId(), task.parentId(), RunData.class);
    if (d.revision() != run.data().requirementsVersion()
        || Set.of("COMPLETED", "CANCELLED").contains(run.data().status()))
      throw WorkspaceFailure.invalid("Запуск или ревизия закрыты");
    if (d.authorSessionId() != null) {
      var session =
          Records.require(
              tx,
              EntityKind.AGENT_SESSION,
              actor.accountId(),
              d.authorSessionId(),
              AgentSessionData.class);
      if (!Set.of("FAILED", "CANCELLED", "INTERRUPTED", "PAUSED").contains(session.data().status()))
        throw WorkspaceFailure.invalid("Предыдущее назначение ещё активно");
      if (tx
          .all(
              EntityKind.TOOL_OPERATION,
              actor.accountId(),
              task.projectId(),
              null,
              ToolOperationData.class)
          .stream()
          .anyMatch(
              op ->
                  d.authorSessionId().equals(op.data().sessionId())
                      && Set.of("UNKNOWN", "RUNNING", "QUEUED", "RECONCILING")
                          .contains(op.data().status())))
        throw new WorkspaceFailure(
            409, "operation_unknown", "Сначала определите исход предыдущих действий");
    }
    var value =
        new TaskData(
                d.title(),
                d.criteria(),
                d.dependencies(),
                d.role(),
                d.paths(),
                "READY",
                null,
                d.artifactId(),
                d.parentSessionId())
            .atRevision(d.revision());
    var next = records.change(tx, EntityKind.TASK, task, value);
    var r = run.data();
    if (Set.of("WAITING", "INTERRUPTED").contains(r.status()))
      records.change(
          tx,
          EntityKind.RUN,
          run,
          new RunData(r.goal(), "RUNNING", r.planId(), r.requirementsVersion(), null));
    return next;
  }

  public Entity<GenerationData> retryConversation(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var old =
        Records.require(tx, EntityKind.GENERATION, actor.accountId(), id, GenerationData.class);
    Records.version(old, version);
    var d = old.data();
    if (d.sessionId() != null || !Set.of("FAILED", "INTERRUPTED", "CANCELLED").contains(d.status()))
      throw WorkspaceFailure.invalid("Генерация не может быть повторена вручную");
    var conversation =
        Records.require(
            tx,
            EntityKind.CONVERSATION,
            actor.accountId(),
            d.conversationId(),
            ConversationData.class);
    if (!conversation.data().mode().equals("WORK"))
      throw WorkspaceFailure.invalid("Используйте продолжение запуска");
    return conversations.sendMessage(
        tx,
        actor,
        conversation.id(),
        "Продолжи ответ на последнее сообщение, учитывая сохранённую частичную запись.");
  }
}
