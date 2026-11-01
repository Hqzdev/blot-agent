package dev.blot.application.workspace.review;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.ReviewData;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.agent.AttemptData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

public final class ReviewService {
  public record Decision(String decision, List<String> findings) {}

  private final Records records;

  public ReviewService(Records records) {
    this.records = records;
  }

  public Entity<ReviewData> submit(
      WorkspaceStore.Transaction tx, Entity<AgentSessionData> reviewer, Decision decision) {
    if (!reviewer.data().role().equals("REVIEWER"))
      throw new WorkspaceFailure(403, "forbidden", "Нужна независимая проверка");
    var task =
        Records.require(
            tx, EntityKind.TASK, reviewer.ownerId(), reviewer.data().taskId(), TaskData.class);
    if (reviewer.id().equals(task.data().authorSessionId())
        || task.data().artifactId() == null
        || !task.data().status().equals("REVIEW"))
      throw WorkspaceFailure.invalid("Нет актуального результата для независимого ревью");
    var artifact =
        Records.require(
            tx,
            EntityKind.ARTIFACT,
            reviewer.ownerId(),
            task.data().artifactId(),
            ArtifactData.class);
    if (!Set.of("accepted", "changes_requested").contains(decision.decision())
        || decision.findings() == null
        || decision.decision().equals("accepted") && !decision.findings().isEmpty())
      throw WorkspaceFailure.invalid("Неверное решение ревью");
    var review =
        records.create(
            tx,
            EntityKind.REVIEW,
            reviewer.ownerId(),
            reviewer.projectId(),
            task.id(),
            new ReviewData(
                task.id(),
                artifact.id(),
                artifact.data().hash(),
                task.data().authorSessionId(),
                reviewer.id(),
                decision.decision(),
                decision.findings()));
    var d = task.data();
    records.change(
        tx,
        EntityKind.TASK,
        task,
        new TaskData(
                d.title(),
                d.criteria(),
                d.dependencies(),
                d.role(),
                d.paths(),
                decision.decision().equals("accepted") ? "ACCEPTED" : "READY",
                d.authorSessionId(),
                d.artifactId(),
                d.parentSessionId())
            .atRevision(d.revision()));
    for (var attempt :
        tx.list(
            EntityKind.TASK_ATTEMPT,
            reviewer.ownerId(),
            reviewer.projectId(),
            task.id(),
            AttemptData.class,
            10000)) {
      if (attempt.data().sessionId().equals(task.data().authorSessionId())) {
        var a = attempt.data();
        records.change(
            tx,
            EntityKind.TASK_ATTEMPT,
            attempt,
            new AttemptData(
                a.sessionId(),
                a.number(),
                a.baseSha(),
                decision.decision().equals("accepted") ? "ACCEPTED" : "CHANGES_REQUESTED",
                a.artifactId(),
                null));
      }
    }
    return review;
  }
}
