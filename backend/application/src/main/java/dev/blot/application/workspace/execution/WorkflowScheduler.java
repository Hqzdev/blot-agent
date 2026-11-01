package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.integrations.IntegrationService;
import dev.blot.application.workspace.profile.ProfileService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.agent.AssignmentData;
import dev.blot.core.workspace.agent.AttemptData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import dev.blot.core.workspace.projects.WorkspaceCleanupData;
import dev.blot.core.workspace.skills.SkillData;
import java.nio.file.*;
import java.util.*;

/** Готовность задачи проверяется по сохранённым принятым зависимостям. */
public final class WorkflowScheduler {
  private final WorkspaceStore store;
  private final Records records;
  private final ConversationService conversations;
  private final GitGateway git;
  private final ProfileService profiles;
  private final IntegrationService integration;
  private final ArtifactStore artifacts;

  public WorkflowScheduler(
      WorkspaceStore store,
      Records records,
      ConversationService conversations,
      GitGateway git,
      ProfileService profiles,
      IntegrationService integration,
      ArtifactStore artifacts) {
    this.integration = integration;
    this.artifacts = artifacts;
    this.store = store;
    this.records = records;
    this.conversations = conversations;
    this.git = git;
    this.profiles = profiles;
  }

  public void tick() {
    wakeParents();
    var runs =
        store
            .transact(tx -> tx.states(EntityKind.RUN, RunData.class, List.of("RUNNING"), 10000))
            .stream()
            .filter(e -> e.data().status().equals("RUNNING"))
            .toList();
    for (var run : runs) {
      integration.advance(run);
      var tasks =
          store.transact(
              tx ->
                  tx.list(
                      EntityKind.TASK,
                      run.ownerId(),
                      run.projectId(),
                      run.id(),
                      TaskData.class,
                      10000));
      for (var task : tasks) {
        if (!task.data().status().equals("READY")
            || task.data().revision() != run.data().requirementsVersion()) continue;
        boolean ready =
            task.data().dependencies().stream()
                .allMatch(
                    id ->
                        tasks.stream()
                            .anyMatch(
                                t -> t.id().equals(id) && t.data().status().equals("ACCEPTED")));
        if (ready) {
          try {
            start(run, task, "AUTHOR", null);
          } catch (WorkspaceFailure failure) {
            store.transact(
                tx -> {
                  var current =
                      tx.find(EntityKind.RUN, run.ownerId(), run.id(), RunData.class).orElse(null);
                  if (current == null
                      || !current.data().status().equals("RUNNING")
                      || current.data().requirementsVersion() != run.data().requirementsVersion())
                    return null;
                  var d = current.data();
                  records.change(
                      tx,
                      EntityKind.RUN,
                      current,
                      new RunData(
                          d.goal(),
                          "WAITING",
                          d.planId(),
                          d.requirementsVersion(),
                          failure.code()));
                  return null;
                });
          }
          return;
        }
      }
    }
  }

  private void start(
      Entity<RunData> run, Entity<TaskData> task, String phase, Entity<AgentSessionData> author) {
    var preparing =
        store.transact(
            tx -> {
              var current =
                  Records.require(tx, EntityKind.RUN, run.ownerId(), run.id(), RunData.class);
              if (!current.data().status().equals("RUNNING")
                  || current.data().requirementsVersion() != task.data().revision()) return null;
              var project =
                  Records.require(
                      tx, EntityKind.PROJECT, run.ownerId(), run.projectId(), ProjectData.class);
              return records.create(
                  tx,
                  EntityKind.WORKSPACE_CLEANUP,
                  run.ownerId(),
                  run.projectId(),
                  run.id(),
                  new WorkspaceCleanupData(
                      run.projectId(),
                      run.id(),
                      project.data().repositoryPath(),
                      "PREPARING",
                      null));
            });
    if (preparing == null) return;
    try {
      prepareSession(run, task, phase, author);
    } finally {
      // Удаление проекта ждёт эту запись даже после команды stop.
      store.transact(
          tx -> {
            tx.delete(EntityKind.WORKSPACE_CLEANUP, preparing.ownerId(), preparing.id());
            return null;
          });
    }
  }

  private void prepareSession(
      Entity<RunData> run, Entity<TaskData> task, String phase, Entity<AgentSessionData> author) {
    String role = phase.equals("REVIEW") ? "REVIEWER" : task.data().role();
    UUID id = UUID.randomUUID();
    var project =
        store.transact(
            tx ->
                Records.require(
                    tx, EntityKind.PROJECT, run.ownerId(), run.projectId(), ProjectData.class));
    Path workspace =
        author == null
            ? git.createWorkspace(Path.of(project.data().repositoryPath()), run.id(), id)
            : Path.of(author.data().workspace());
    if (author == null) {
      for (UUID dependency : task.data().dependencies()) {
        var input =
            store.transact(
                tx ->
                    Records.require(
                        tx, EntityKind.TASK, run.ownerId(), dependency, TaskData.class));
        if (input.data().artifactId() != null) {
          var artifact =
              store.transact(
                  tx ->
                      Records.require(
                          tx,
                          EntityKind.ARTIFACT,
                          run.ownerId(),
                          input.data().artifactId(),
                          ArtifactData.class));
          var bytes = new java.io.ByteArrayOutputStream();
          for (int offset = 0; offset < 16_777_216; offset += 1_048_576) {
            byte[] part =
                artifacts.read(
                    artifact.data().relativePath(), artifact.data().hash(), offset, 1_048_576);
            bytes.writeBytes(part);
            if (part.length < 1_048_576) break;
          }
          git.integrate(workspace, bytes.toString(java.nio.charset.StandardCharsets.UTF_8));
        }
      }
    }
    store.transact(
        tx -> {
          var freshRun =
              Records.require(tx, EntityKind.RUN, run.ownerId(), run.id(), RunData.class);
          if (!freshRun.data().status().equals("RUNNING")
              || freshRun.data().requirementsVersion() != task.data().revision()) return null;
          var fresh =
              Records.require(tx, EntityKind.TASK, run.ownerId(), task.id(), TaskData.class);
          if (!fresh.data().status().equals(phase.equals("REVIEW") ? "REVIEW" : "READY"))
            return null;
          var conversation =
              records.create(
                  tx,
                  EntityKind.CONVERSATION,
                  run.ownerId(),
                  run.projectId(),
                  id,
                  new ConversationData(task.data().title(), "AGENT", run.id(), false));
          String instruction =
              profiles.instruction(tx, run.ownerId(), run.projectId(), role)
                  + "\nЦель запуска: "
                  + run.data().goal()
                  + "\nЗадача: "
                  + task.data().title()
                  + "\nКритерии: "
                  + task.data().criteria()
                  + "\nРазрешённые пути: "
                  + task.data().paths()
                  + "\n"
                  + (phase.equals("REVIEW")
                      ? "Верни JSON {\"decision\":\"accepted|changes_requested\",\"findings\":[\"замечание\"]}. Артефакт: "
                          + task.data().artifactId()
                      : "Используй инструменты. Завершай только с фактическим результатом и описанием проверок.");
          String skills =
              tx.list(EntityKind.SKILL, run.ownerId(), null, null, SkillData.class, 10000).stream()
                  .filter(
                      e ->
                          e.data().enabled()
                              && e.data().roles().contains(role)
                              && (e.projectId() == null || e.projectId().equals(run.projectId())))
                  .map(
                      e ->
                          "Навык "
                              + e.id()
                              + " версия "
                              + e.version()
                              + ": "
                              + e.data().instruction())
                  .collect(java.util.stream.Collectors.joining("\n"));
          instruction += "\nНавыки задают рабочие указания без новых прав:\n" + skills;
          var session =
              new Entity<>(
                  id,
                  run.ownerId(),
                  run.projectId(),
                  run.id(),
                  0,
                  conversation.createdAt(),
                  conversation.createdAt(),
                  new AgentSessionData(
                      role,
                      instruction,
                      task.id(),
                      conversation.id(),
                      author == null ? task.data().parentSessionId() : author.id(),
                      task.data().parentSessionId() == null ? 0 : 1,
                      workspace.toString(),
                      "QUEUED",
                      null,
                      0));
          tx.insert(EntityKind.AGENT_SESSION, session);
          var configuration =
              profiles.freeze(
                  tx, run.ownerId(), run.projectId(), role, session.data().parentSessionId());
          records.create(
              tx,
              EntityKind.AGENT_CONFIGURATION,
              run.ownerId(),
              run.projectId(),
              id,
              configuration);
          records.create(
              tx,
              EntityKind.ASSIGNMENT,
              run.ownerId(),
              run.projectId(),
              task.id(),
              new AssignmentData(
                  task.id(),
                  id,
                  role,
                  "Выбрана роль задачи; зависимости приняты; сессия изолирована"));
          if (author == null) {
            int number =
                tx.list(
                            EntityKind.TASK_ATTEMPT,
                            run.ownerId(),
                            run.projectId(),
                            task.id(),
                            AttemptData.class,
                            10000)
                        .size()
                    + 1;
            records.create(
                tx,
                EntityKind.TASK_ATTEMPT,
                run.ownerId(),
                run.projectId(),
                task.id(),
                new AttemptData(id, number, project.data().baseSha(), "RUNNING", null, null));
          }
          tx.event(run.ownerId(), run.projectId(), "agent_session.created", Map.of("id", id));
          if (author == null) {
            var d = fresh.data();
            records.change(
                tx,
                EntityKind.TASK,
                fresh,
                new TaskData(
                        d.title(),
                        d.criteria(),
                        d.dependencies(),
                        d.role(),
                        d.paths(),
                        "RUNNING",
                        id,
                        d.artifactId(),
                        d.parentSessionId())
                    .atRevision(d.revision()));
          }
          conversations.append(
              tx,
              run.ownerId(),
              run.projectId(),
              conversation.id(),
              "user",
              instruction,
              null,
              null,
              null);
          records.create(
              tx,
              EntityKind.GENERATION,
              run.ownerId(),
              run.projectId(),
              conversation.id(),
              new GenerationData(conversation.id(), id, "QUEUED", null, null, null));
          return null;
        });
  }

  private void wakeParents() {
    store.transact(
        tx -> {
          for (var job : tx.scan(EntityKind.GENERATION, GenerationData.class, 10000)) {
            if (!job.data().status().equals("BLOCKED") || !"child_wait".equals(job.data().error()))
              continue;
            var session =
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    job.data().sessionId(),
                    AgentSessionData.class);
            var children =
                tx
                    .list(
                        EntityKind.TASK,
                        job.ownerId(),
                        job.projectId(),
                        session.parentId(),
                        TaskData.class,
                        10000)
                    .stream()
                    .filter(t -> session.id().equals(t.data().parentSessionId()))
                    .toList();
            if (children.stream()
                .allMatch(
                    t -> Set.of("ACCEPTED", "FAILED", "CANCELLED").contains(t.data().status()))) {
              var d = job.data();
              records.change(
                  tx,
                  EntityKind.GENERATION,
                  job,
                  new GenerationData(
                      d.conversationId(),
                      d.sessionId(),
                      "QUEUED",
                      null,
                      d.inputTokens(),
                      d.outputTokens()));
            }
          }
          return null;
        });
  }

  public void review(Entity<AgentSessionData> author) {
    var run =
        store.transact(
            tx ->
                Records.require(
                    tx, EntityKind.RUN, author.ownerId(), author.parentId(), RunData.class));
    var task =
        store.transact(
            tx ->
                Records.require(
                    tx, EntityKind.TASK, author.ownerId(), author.data().taskId(), TaskData.class));
    start(run, task, "REVIEW", author);
  }
}
