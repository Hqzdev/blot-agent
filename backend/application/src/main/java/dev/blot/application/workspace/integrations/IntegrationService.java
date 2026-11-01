package dev.blot.application.workspace.integrations;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

/** Итоговые этапы добавляет сервер, поэтому модель не может убрать их из плана. */
public final class IntegrationService {
  private final WorkspaceStore store;
  private final Records records;

  public IntegrationService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public void advance(Entity<RunData> run) {
    store.transact(
        tx -> {
          var fresh = Records.require(tx, EntityKind.RUN, run.ownerId(), run.id(), RunData.class);
          if (!fresh.data().status().equals("RUNNING")) return null;
          var tasks =
              tx
                  .list(
                      EntityKind.TASK,
                      run.ownerId(),
                      run.projectId(),
                      run.id(),
                      TaskData.class,
                      10000)
                  .stream()
                  .filter(t -> t.data().revision() == run.data().requirementsVersion())
                  .toList();
          if (tasks.isEmpty()
              || tasks.stream().anyMatch(t -> !t.data().status().equals("ACCEPTED"))) return null;
          var markers =
              tx
                  .list(
                      EntityKind.CHECKPOINT,
                      run.ownerId(),
                      run.projectId(),
                      run.id(),
                      Map.class,
                      10000)
                  .stream()
                  .filter(
                      m ->
                          ((Number) m.data().getOrDefault("revision", 1)).longValue()
                              == run.data().requirementsVersion())
                  .toList();
          var integration =
              markers.stream().filter(m -> "integration".equals(m.data().get("phase"))).findFirst();
          if (integration.isEmpty()) {
            var t =
                records.create(
                    tx,
                    EntityKind.TASK,
                    run.ownerId(),
                    run.projectId(),
                    run.id(),
                    new TaskData(
                            "Объединить принятые результаты",
                            List.of(
                                "Согласовать все принятые изменения без потери требований",
                                "Сохранить итоговую копию и устранить конфликты"),
                            tasks.stream().map(Entity::id).toList(),
                            "INTEGRATOR",
                            List.of("."),
                            "READY",
                            null,
                            null)
                        .atRevision(run.data().requirementsVersion()));
            records.create(
                tx,
                EntityKind.CHECKPOINT,
                run.ownerId(),
                run.projectId(),
                run.id(),
                Map.of(
                    "phase",
                    "integration",
                    "taskId",
                    t.id(),
                    "revision",
                    run.data().requirementsVersion()));
            return null;
          }
          var checks =
              markers.stream()
                  .filter(m -> "final_checks".equals(m.data().get("phase")))
                  .findFirst();
          UUID integrationId = UUID.fromString(integration.get().data().get("taskId").toString());
          if (checks.isEmpty()) {
            var qa =
                records.create(
                    tx,
                    EntityKind.TASK,
                    run.ownerId(),
                    run.projectId(),
                    run.id(),
                    new TaskData(
                            "Проверить итоговую версию",
                            List.of(
                                "Запустить подходящую проверку через process_run и получить exitCode 0",
                                "Не изменять исходный код результата"),
                            List.of(integrationId),
                            "QA",
                            List.of("."),
                            "READY",
                            null,
                            null)
                        .atRevision(run.data().requirementsVersion()));
            var security =
                records.create(
                    tx,
                    EntityKind.TASK,
                    run.ownerId(),
                    run.projectId(),
                    run.id(),
                    new TaskData(
                            "Проверить безопасность итоговой версии",
                            List.of(
                                "Изучить фактические изменения и проверить границы доверия",
                                "Перечислить конкретные проверенные файлы и обнаруженные ограничения"),
                            List.of(integrationId),
                            "SECURITY",
                            List.of("."),
                            "READY",
                            null,
                            null)
                        .atRevision(run.data().requirementsVersion()));
            records.create(
                tx,
                EntityKind.CHECKPOINT,
                run.ownerId(),
                run.projectId(),
                run.id(),
                Map.of(
                    "phase",
                    "final_checks",
                    "qaTaskId",
                    qa.id(),
                    "securityTaskId",
                    security.id(),
                    "revision",
                    run.data().requirementsVersion()));
            return null;
          }
          UUID qaId = UUID.fromString(checks.get().data().get("qaTaskId").toString());
          var qa = Records.require(tx, EntityKind.TASK, run.ownerId(), qaId, TaskData.class);
          var integrationTask =
              Records.require(tx, EntityKind.TASK, run.ownerId(), integrationId, TaskData.class);
          var integratedArtifact =
              Records.require(
                  tx,
                  EntityKind.ARTIFACT,
                  run.ownerId(),
                  integrationTask.data().artifactId(),
                  ArtifactData.class);
          UUID securityId = UUID.fromString(checks.get().data().get("securityTaskId").toString());
          var securityTask =
              Records.require(tx, EntityKind.TASK, run.ownerId(), securityId, TaskData.class);
          var qaArtifact =
              Records.require(
                  tx,
                  EntityKind.ARTIFACT,
                  run.ownerId(),
                  qa.data().artifactId(),
                  ArtifactData.class);
          var securityArtifact =
              Records.require(
                  tx,
                  EntityKind.ARTIFACT,
                  run.ownerId(),
                  securityTask.data().artifactId(),
                  ArtifactData.class);
          if (!qaArtifact.data().hash().equals(integratedArtifact.data().hash())
              || !securityArtifact.data().hash().equals(integratedArtifact.data().hash())) {
            var d = fresh.data();
            records.change(
                tx,
                EntityKind.RUN,
                fresh,
                new RunData(
                    d.goal(),
                    "WAITING",
                    d.planId(),
                    d.requirementsVersion(),
                    "final_artifact_changed"));
            return null;
          }
          boolean passed =
              tx
                  .list(
                      EntityKind.TOOL_OPERATION,
                      run.ownerId(),
                      run.projectId(),
                      null,
                      ToolOperationData.class,
                      10000)
                  .stream()
                  .anyMatch(
                      op ->
                          Objects.equals(qa.data().authorSessionId(), op.data().sessionId())
                              && op.data().name().equals("process.run")
                              && op.data().status().equals("FINISHED")
                              && op.data().result() instanceof Map<?, ?> result
                              && result.get("exitCode") instanceof Number code
                              && code.intValue() == 0);
          boolean inspected =
              tx
                  .all(
                      EntityKind.TOOL_OPERATION,
                      run.ownerId(),
                      run.projectId(),
                      null,
                      ToolOperationData.class)
                  .stream()
                  .anyMatch(
                      op ->
                          Objects.equals(
                                  securityTask.data().authorSessionId(), op.data().sessionId())
                              && op.data().status().equals("FINISHED")
                              && op.data().name().equals("project.read.file"));
          passed = passed && inspected;
          var d = fresh.data();
          records.change(
              tx,
              EntityKind.RUN,
              fresh,
              new RunData(
                  d.goal(),
                  passed ? "READY_FOR_ACCEPTANCE" : "WAITING",
                  d.planId(),
                  d.requirementsVersion(),
                  passed ? "user_acceptance" : "final_check_evidence_missing"));
          return null;
        });
  }

  public Entity<RunData> accept(WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var run = Records.require(tx, EntityKind.RUN, actor.accountId(), id, RunData.class);
    Records.version(run, version);
    if (!run.data().status().equals("READY_FOR_ACCEPTANCE"))
      throw new WorkspaceFailure(409, "gate_not_satisfied", "Не завершены обязательные проверки");
    var tasks =
        tx
            .list(
                EntityKind.TASK,
                actor.accountId(),
                run.projectId(),
                run.id(),
                TaskData.class,
                10000)
            .stream()
            .filter(t -> t.data().revision() == run.data().requirementsVersion())
            .toList();
    if (tasks.isEmpty() || tasks.stream().anyMatch(t -> !t.data().status().equals("ACCEPTED")))
      throw new WorkspaceFailure(409, "gate_not_satisfied", "Есть непринятые задачи");
    records.create(
        tx,
        EntityKind.CHECKPOINT,
        actor.accountId(),
        run.projectId(),
        run.id(),
        Map.of(
            "phase",
            "final_report",
            "goal",
            run.data().goal(),
            "taskIds",
            tasks.stream().map(Entity::id).toList(),
            "artifactIds",
            tasks.stream().map(t -> t.data().artifactId()).filter(Objects::nonNull).toList(),
            "acceptedBy",
            actor.accountId()));
    var d = run.data();
    return records.change(
        tx,
        EntityKind.RUN,
        run,
        new RunData(d.goal(), "COMPLETED", d.planId(), d.requirementsVersion(), null));
  }
}
