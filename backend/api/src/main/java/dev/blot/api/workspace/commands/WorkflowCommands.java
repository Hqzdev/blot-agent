package dev.blot.api.workspace.commands;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.application.workspace.integrations.IntegrationService;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.application.workspace.projects.ProjectService;
import dev.blot.core.Project;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.projects.RunData;
import java.util.*;

public final class WorkflowCommands {
  record Project(String name, String repositoryPath) {}

  record Goal(UUID id, String goal, Long tokenBudget) {}

  record Id(UUID id) {}

  record Grant(UUID id, int seconds, int uses) {}

  record Answer(UUID id, String answer) {}

  public WorkflowCommands(
      CommandDispatcher dispatcher,
      JsonCodec json,
      ProjectService projects,
      RunService runs,
      PermissionService permissions,
      Records records,
      IntegrationService integration) {
    dispatcher.registerPrepared(
        "project.create",
        (actor, command) -> {
          var payload = json.convert(command.payload(), Project.class);
          var project = projects.inspect(actor, payload.name(), payload.repositoryPath());
          return (tx, current, original) -> projects.create(tx, current, project);
        });
    dispatcher.register(
        "project.access",
        (tx, a, c) -> projects.restoreAccess(tx, a, json.convert(c.payload(), Id.class).id()));
    dispatcher.register(
        "project.archive",
        (tx, a, c) -> {
          projects.archive(tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion());
          return Map.of("archived", true);
        });
    dispatcher.register(
        "run.accept",
        (tx, a, c) ->
            integration.accept(
                tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion()));
    dispatcher.register(
        "run.create",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), Goal.class);
          return runs.create(tx, a, c.projectId(), p.goal(), p.tokenBudget());
        });
    dispatcher.register(
        "run.plan.approve",
        (tx, a, c) ->
            runs.approve(tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion()));
    for (String action : List.of("pause", "resume", "stop"))
      dispatcher.register(
          "run." + action,
          (tx, a, c) ->
              runs.control(
                  tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion(), action));
    dispatcher.register(
        "run.steer",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), Goal.class);
          return runs.steer(tx, a, p.id(), c.expectedVersion(), p.goal());
        });
    dispatcher.register(
        "permission.grant",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), Grant.class);
          var result = permissions.grant(tx, a, p.id(), c.expectedVersion(), p.seconds(), p.uses());
          var action =
              Records.require(
                  tx, EntityKind.PREPARED_ACTION, a.accountId(), p.id(), PreparedActionData.class);
          wake(tx, a.accountId(), action.data().sessionId(), records);
          return result;
        });
    dispatcher.register(
        "permission.deny",
        (tx, a, c) -> {
          var id = json.convert(c.payload(), Id.class).id();
          var action =
              Records.require(
                  tx, EntityKind.PREPARED_ACTION, a.accountId(), id, PreparedActionData.class);
          Records.version(action, c.expectedVersion());
          var d = action.data();
          if (!d.status().equals("PREPARED"))
            throw WorkspaceFailure.conflict("Действие уже начато или закрыто");
          var result =
              records.change(
                  tx,
                  EntityKind.PREPARED_ACTION,
                  action,
                  new PreparedActionData(
                      d.capability(),
                      d.sessionId(),
                      d.taskId(),
                      d.baseSha(),
                      d.arguments(),
                      d.hash(),
                      "DENIED"));
          wake(tx, a.accountId(), d.sessionId(), records);
          return result;
        });
    dispatcher.register(
        "permission.revoke",
        (tx, a, c) -> {
          permissions.revoke(tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion());
          return Map.of("revoked", true);
        });
    dispatcher.register(
        "user.answer",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), Answer.class);
          var q = Records.require(tx, EntityKind.CHECKPOINT, a.accountId(), p.id(), Map.class);
          Records.version(q, c.expectedVersion());
          if (!Boolean.TRUE.equals(q.data().get("open")))
            throw WorkspaceFailure.invalid("Вопрос закрыт");
          var answer = Records.text(p.answer(), "answer", 8000);
          var answered = new LinkedHashMap<String, Object>(q.data());
          answered.put("open", false);
          answered.put("answer", answer);
          records.change(tx, EntityKind.CHECKPOINT, q, answered);
          if (Boolean.TRUE.equals(q.data().get("planning"))) {
            var run =
                Records.require(tx, EntityKind.RUN, a.accountId(), q.parentId(), RunData.class);
            long revision = ((Number) q.data().get("revision")).longValue();
            if (revision != run.data().requirementsVersion()
                || !run.data().status().equals("WAITING"))
              throw WorkspaceFailure.conflict("Требования или состояние запуска изменились");
            UUID conversation = UUID.fromString(q.data().get("conversationId").toString());
            new ConversationService(records)
                .append(
                    tx,
                    a.accountId(),
                    run.projectId(),
                    conversation,
                    "user",
                    answer,
                    null,
                    null,
                    null);
            var d = run.data();
            records.change(
                tx,
                EntityKind.RUN,
                run,
                new RunData(d.goal(), "PLANNING", null, d.requirementsVersion(), null));
            for (var generation :
                tx.list(
                    EntityKind.GENERATION,
                    a.accountId(),
                    run.projectId(),
                    conversation,
                    GenerationData.class,
                    10000)) {
              var g = generation.data();
              if (Set.of("BLOCKED", "RUNNING").contains(g.status()))
                records.change(
                    tx,
                    EntityKind.GENERATION,
                    generation,
                    new GenerationData(
                        g.conversationId(),
                        null,
                        "QUEUED",
                        null,
                        g.inputTokens(),
                        g.outputTokens()));
            }
            return Map.of("answered", true);
          }
          /* answer сохранён выше; сессия получает сообщение и продолжает работу. */
          var session =
              Records.require(
                  tx,
                  EntityKind.AGENT_SESSION,
                  a.accountId(),
                  q.parentId(),
                  AgentSessionData.class);
          new ConversationService(records)
              .append(
                  tx,
                  a.accountId(),
                  session.projectId(),
                  session.data().conversationId(),
                  "user",
                  answer,
                  null,
                  null,
                  null);
          wake(tx, a.accountId(), session.id(), records);
          return Map.of("answered", true);
        });
  }

  private static void wake(
      WorkspaceStore.Transaction tx, UUID owner, UUID sessionId, Records records) {
    var s = Records.require(tx, EntityKind.AGENT_SESSION, owner, sessionId, AgentSessionData.class);
    var run = Records.require(tx, EntityKind.RUN, owner, s.parentId(), RunData.class);
    if (!run.data().status().equals("RUNNING")) return;
    if (tx.list(EntityKind.CHECKPOINT, owner, s.projectId(), sessionId, Map.class, 10000).stream()
        .anyMatch(e -> Boolean.TRUE.equals(e.data().get("open")))) return;
    for (var g :
        tx.list(
            EntityKind.GENERATION,
            owner,
            null,
            s.data().conversationId(),
            GenerationData.class,
            10000)) {
      var d = g.data();
      if (d.status().equals("BLOCKED"))
        records.change(
            tx,
            EntityKind.GENERATION,
            g,
            new GenerationData(
                d.conversationId(),
                d.sessionId(),
                "QUEUED",
                null,
                d.inputTokens(),
                d.outputTokens()));
    }
  }
}
