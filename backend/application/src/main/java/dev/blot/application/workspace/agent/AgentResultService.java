package dev.blot.application.workspace.agent;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.execution.WorkflowScheduler;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.review.ReviewService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.agent.AttemptData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Фиксирует снимок исполнителя или решение независимого reviewer. */
public final class AgentResultService {
  private final WorkspaceStore store;
  private final Records records;
  private final ReviewService reviews;
  private final GitGateway git;
  private final ArtifactStore artifacts;
  private final WorkflowScheduler scheduler;
  private final JsonCodec json;

  public AgentResultService(
      WorkspaceStore store,
      Records records,
      ReviewService reviews,
      GitGateway git,
      ArtifactStore artifacts,
      WorkflowScheduler scheduler,
      JsonCodec json) {
    this.store = store;
    this.records = records;
    this.reviews = reviews;
    this.git = git;
    this.artifacts = artifacts;
    this.scheduler = scheduler;
    this.json = json;
  }

  public void complete(
      Entity<GenerationData> job, Entity<AgentSessionData> session, ProviderGateway.Reply reply) {
    store.transact(
        tx -> {
          boolean uncertain =
              tx
                  .all(
                      EntityKind.TOOL_OPERATION,
                      job.ownerId(),
                      job.projectId(),
                      null,
                      ToolOperationData.class)
                  .stream()
                  .anyMatch(
                      op ->
                          session.id().equals(op.data().sessionId())
                              && Set.of("UNKNOWN", "RECONCILING", "RUNNING")
                                  .contains(op.data().status()));
          if (uncertain)
            throw new WorkspaceFailure(
                409, "operation_unknown", "Сначала определите исход незавершённых операций");
          return null;
        });
    var d = session.data();
    if (d.role().equals("REVIEWER")) {
      var decision = json.read(unfence(reply.text()), ReviewService.Decision.class);
      var checkedTask =
          store.transact(
              tx ->
                  Records.require(tx, EntityKind.TASK, job.ownerId(), d.taskId(), TaskData.class));
      var checkedArtifact =
          store.transact(
              tx ->
                  Records.require(
                      tx,
                      EntityKind.ARTIFACT,
                      job.ownerId(),
                      checkedTask.data().artifactId(),
                      ArtifactData.class));
      String currentHash = new TokenGenerator().digest(git.snapshot(Path.of(d.workspace())));
      if (!currentHash.equals(checkedArtifact.data().hash()))
        throw new WorkspaceFailure(409, "action_invalidated", "Результат изменился во время ревью");
      store.transact(
          tx -> {
            reviews.submit(tx, session, decision);
            return null;
          });
    } else {
      String patch = git.snapshot(Path.of(d.workspace()));
      var saved = artifacts.write(patch.getBytes(StandardCharsets.UTF_8));
      String base = git.inspect(Path.of(d.workspace())).baseSha();
      store.transact(
          tx -> {
            var artifact =
                records.create(
                    tx,
                    EntityKind.ARTIFACT,
                    job.ownerId(),
                    job.projectId(),
                    d.taskId(),
                    new ArtifactData(
                        saved.hash(),
                        "text/x-diff",
                        saved.relativePath(),
                        base,
                        session.id(),
                        d.taskId()));
            var task =
                Records.require(tx, EntityKind.TASK, job.ownerId(), d.taskId(), TaskData.class);
            var t = task.data();
            records.change(
                tx,
                EntityKind.TASK,
                task,
                new TaskData(
                        t.title(),
                        t.criteria(),
                        t.dependencies(),
                        t.role(),
                        t.paths(),
                        "REVIEW",
                        session.id(),
                        artifact.id(),
                        t.parentSessionId())
                    .atRevision(t.revision()));
            for (var attempt :
                tx.list(
                    EntityKind.TASK_ATTEMPT,
                    job.ownerId(),
                    job.projectId(),
                    d.taskId(),
                    AttemptData.class,
                    10000)) {
              if (attempt.data().sessionId().equals(session.id())) {
                var a = attempt.data();
                records.change(
                    tx,
                    EntityKind.TASK_ATTEMPT,
                    attempt,
                    new AttemptData(
                        a.sessionId(), a.number(), a.baseSha(), "REVIEW", artifact.id(), null));
              }
            }
            return null;
          });
      scheduler.review(session);
    }
    store.transact(
        tx -> {
          var current =
              Records.require(
                  tx,
                  EntityKind.AGENT_SESSION,
                  job.ownerId(),
                  session.id(),
                  AgentSessionData.class);
          var v = current.data();
          records.change(
              tx,
              EntityKind.AGENT_SESSION,
              current,
              new AgentSessionData(
                  v.role(),
                  v.instruction(),
                  v.taskId(),
                  v.conversationId(),
                  v.parentSessionId(),
                  v.depth(),
                  v.workspace(),
                  "COMPLETED",
                  null,
                  v.turns()));
          return null;
        });
  }

  private static String unfence(String text) {
    String s = text.strip();
    if (s.startsWith("```")) {
      int first = s.indexOf('\n');
      int last = s.lastIndexOf("```");
      if (first >= 0 && last > first) s = s.substring(first + 1, last);
    }
    return s;
  }
}
