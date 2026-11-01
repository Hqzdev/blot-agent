package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.identity.GrantData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Переходы генерации и контрольные точки восстановления. */
public final class GenerationStateService {
  private final WorkspaceStore store;
  private final Records records;

  public GenerationStateService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public boolean cancelled(Entity<GenerationData> job) {
    if (Thread.currentThread().isInterrupted()) return true;
    return store.transact(
        tx -> {
          var g =
              Records.require(
                  tx, EntityKind.GENERATION, job.ownerId(), job.id(), GenerationData.class);
          if (g.data().status().equals("CANCELLED")) return true;
          if (g.data().sessionId() != null) {
            var s =
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    g.data().sessionId(),
                    AgentSessionData.class);
            if (s.data().parentSessionId() != null) {
              var parent =
                  Records.require(
                      tx,
                      EntityKind.AGENT_SESSION,
                      job.ownerId(),
                      s.data().parentSessionId(),
                      AgentSessionData.class);
              if (Set.of("CANCELLED", "FAILED", "PAUSED").contains(parent.data().status()))
                return true;
            }
            var run =
                Records.require(tx, EntityKind.RUN, job.ownerId(), s.parentId(), RunData.class);
            var task =
                Records.require(
                    tx, EntityKind.TASK, job.ownerId(), s.data().taskId(), TaskData.class);
            return task.data().revision() != run.data().requirementsVersion()
                || !run.data().status().equals("RUNNING")
                || Set.of("PAUSED", "CANCELLED").contains(s.data().status());
          }
          var conversation =
              Records.require(
                  tx,
                  EntityKind.CONVERSATION,
                  job.ownerId(),
                  g.data().conversationId(),
                  ConversationData.class);
          if (conversation.data().runId() != null) {
            var run =
                Records.require(
                    tx, EntityKind.RUN, job.ownerId(), conversation.data().runId(), RunData.class);
            return conversation.data().mode().equals("PLAN")
                    && conversation.data().requirementsVersion() != run.data().requirementsVersion()
                || !Set.of("PLANNING", "RUNNING").contains(run.data().status());
          }
          return false;
        });
  }

  public void finish(
      Entity<GenerationData> job, String state, String error, ProviderGateway.Reply reply) {
    finish(job, state, error, reply, null);
  }

  public void finish(
      Entity<GenerationData> job,
      String state,
      String error,
      ProviderGateway.Reply reply,
      UUID waitingAction) {
    store.transact(
        tx -> {
          var current =
              Records.require(
                  tx, EntityKind.GENERATION, job.ownerId(), job.id(), GenerationData.class);
          var d = current.data();
          String next = d.status().equals("CANCELLED") ? "CANCELLED" : state;
          if (state.equals("CANCELLED") && d.sessionId() != null) {
            var session =
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    d.sessionId(),
                    AgentSessionData.class);
            var run =
                Records.require(
                    tx, EntityKind.RUN, job.ownerId(), session.parentId(), RunData.class);
            if (run.data().status().equals("PAUSED")) next = "PAUSED";
          }
          if (state.equals("CANCELLED") && d.sessionId() == null) {
            var conversation =
                Records.require(
                    tx,
                    EntityKind.CONVERSATION,
                    job.ownerId(),
                    d.conversationId(),
                    ConversationData.class);
            if (conversation.data().runId() != null) {
              var run =
                  Records.require(
                      tx,
                      EntityKind.RUN,
                      job.ownerId(),
                      conversation.data().runId(),
                      RunData.class);
              if (run.data().status().equals("PAUSED")) next = "PAUSED";
            }
          }
          if (next.equals("BLOCKED")
              && "question_required".equals(error)
              && d.sessionId() == null) {
            var conversation =
                Records.require(
                    tx,
                    EntityKind.CONVERSATION,
                    job.ownerId(),
                    d.conversationId(),
                    ConversationData.class);
            var run =
                Records.require(
                    tx, EntityKind.RUN, job.ownerId(), conversation.data().runId(), RunData.class);
            if (run.data().status().equals("PLANNING")) next = "QUEUED";
          }
          // Подтверждение может прийти до записи BLOCKED. Проверяем сохранённое решение в той же
          // транзакции.
          if (next.equals("BLOCKED")
              && "permission_required".equals(error)
              && d.sessionId() != null) {
            var session =
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    d.sessionId(),
                    AgentSessionData.class);
            boolean openQuestion =
                tx
                    .list(
                        EntityKind.CHECKPOINT,
                        job.ownerId(),
                        job.projectId(),
                        session.id(),
                        Map.class,
                        10000)
                    .stream()
                    .anyMatch(q -> Boolean.TRUE.equals(q.data().get("open")));
            boolean resolved =
                tx
                    .list(
                        EntityKind.PREPARED_ACTION,
                        job.ownerId(),
                        job.projectId(),
                        session.id(),
                        PreparedActionData.class,
                        10000)
                    .stream()
                    .filter(a -> a.id().equals(waitingAction))
                    .anyMatch(
                        a ->
                            a.data().status().equals("DENIED")
                                || tx
                                    .list(
                                        EntityKind.GRANT,
                                        job.ownerId(),
                                        null,
                                        a.id(),
                                        GrantData.class,
                                        10000)
                                    .stream()
                                    .anyMatch(
                                        g ->
                                            !g.data().revoked()
                                                && g.data().usesRemaining() > 0
                                                && g.data()
                                                    .expiresAt()
                                                    .isAfter(java.time.Instant.now())
                                                && g.data().actionHash().equals(a.data().hash())));
            if (!openQuestion && (waitingAction == null || resolved)) next = "QUEUED";
          }
          if (next.equals("FAILED") && d.sessionId() == null) {
            var conversation =
                Records.require(
                    tx,
                    EntityKind.CONVERSATION,
                    job.ownerId(),
                    d.conversationId(),
                    ConversationData.class);
            if (conversation.data().mode().equals("PLAN")) {
              var run =
                  Records.require(
                      tx,
                      EntityKind.RUN,
                      job.ownerId(),
                      conversation.data().runId(),
                      RunData.class);
              var runData = run.data();
              if (runData.status().equals("PLANNING")
                  && conversation.data().requirementsVersion() == runData.requirementsVersion())
                records.change(
                    tx,
                    EntityKind.RUN,
                    run,
                    new RunData(
                        runData.goal(),
                        "WAITING",
                        runData.planId(),
                        runData.requirementsVersion(),
                        error));
            }
          }
          records.change(
              tx,
              EntityKind.GENERATION,
              current,
              new GenerationData(
                  d.conversationId(),
                  d.sessionId(),
                  next,
                  error,
                  reply == null ? null : reply.inputTokens(),
                  reply == null ? null : reply.outputTokens()));
          if (d.sessionId() != null) {
            var session =
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    d.sessionId(),
                    AgentSessionData.class);
            var v = session.data();
            String sessionState =
                switch (next) {
                  case "BLOCKED" -> "WAITING";
                  case "QUEUED" -> "QUEUED";
                  case "PAUSED" -> "PAUSED";
                  case "FAILED" -> "FAILED";
                  case "CANCELLED" -> "CANCELLED";
                  default -> v.status();
                };
            if (!sessionState.equals(v.status()) || error != null)
              records.change(
                  tx,
                  EntityKind.AGENT_SESSION,
                  session,
                  new AgentSessionData(
                      v.role(),
                      v.instruction(),
                      v.taskId(),
                      v.conversationId(),
                      v.parentSessionId(),
                      v.depth(),
                      v.workspace(),
                      sessionState,
                      error,
                      v.turns()));
          }
          return null;
        });
  }

  public void recover() {
    store.transact(
        tx -> {
          for (var g :
              tx.states(EntityKind.GENERATION, GenerationData.class, List.of("RUNNING"), 10000))
            if (g.data().status().equals("RUNNING")) {
              var d = g.data();
              records.change(
                  tx,
                  EntityKind.GENERATION,
                  g,
                  new GenerationData(
                      d.conversationId(),
                      d.sessionId(),
                      "INTERRUPTED",
                      "host_restarted",
                      d.inputTokens(),
                      d.outputTokens()));
            }
          for (var run :
              tx.states(EntityKind.RUN, RunData.class, List.of("RUNNING", "PLANNING"), 10000))
            if (Set.of("RUNNING", "PLANNING").contains(run.data().status())) {
              var d = run.data();
              records.change(
                  tx,
                  EntityKind.RUN,
                  run,
                  new RunData(
                      d.goal(),
                      "INTERRUPTED",
                      d.planId(),
                      d.requirementsVersion(),
                      "recovery_required"));
            }
          return null;
        });
  }
}
