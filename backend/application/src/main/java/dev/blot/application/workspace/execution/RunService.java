package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.WorkspacePaths;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.requirements.RequirementCoverage;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.billing.BudgetData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.planning.CoverageData;
import dev.blot.core.workspace.planning.PlanData;
import dev.blot.core.workspace.planning.PlanStepData;
import dev.blot.core.workspace.planning.RequirementData;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

public final class RunService {
  private final Records records;
  private final ConversationService conversations;
  private final RoleCatalog roles;

  public RunService(Records records, ConversationService conversations, RoleCatalog roles) {
    this.records = records;
    this.conversations = conversations;
    this.roles = roles;
  }

  public Entity<RunData> create(
      WorkspaceStore.Transaction tx, Actor actor, UUID project, String goal, Long tokenBudget) {
    if (tokenBudget != null && tokenBudget < 8192)
      throw WorkspaceFailure.invalid("Слишком маленький бюджет запуска");
    var run = create(tx, actor, project, goal);
    if (tokenBudget != null)
      records.create(
          tx,
          EntityKind.BUDGET,
          actor.accountId(),
          project,
          run.id(),
          new BudgetData(tokenBudget, 0, 0, false));
    return run;
  }

  public Entity<RunData> create(
      WorkspaceStore.Transaction tx, Actor actor, UUID project, String goal) {
    var p = Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    if (p.data().archived()) throw WorkspaceFailure.invalid("Проект в архиве");
    if (p.data().repositoryPath().isBlank())
      throw WorkspaceFailure.invalid(
          "Для работы с кодом подключите Git-репозиторий. Чат доступен без него.");
    var run =
        records.create(
            tx,
            EntityKind.RUN,
            actor.accountId(),
            project,
            null,
            new RunData(Records.text(goal, "goal", 32000), "PLANNING", null, 1, null));
    records.create(
        tx,
        EntityKind.SPECIFICATION,
        actor.accountId(),
        project,
        run.id(),
        Map.of("revision", 1, "content", goal));
    var c =
        records.create(
            tx,
            EntityKind.CONVERSATION,
            actor.accountId(),
            project,
            null,
            new ConversationData(
                    goal.substring(0, Math.min(goal.length(), 100)), "PLAN", run.id(), false)
                .forRequirements(1));
    conversations.append(tx, actor.accountId(), project, c.id(), "user", goal, null, null, null);
    records.create(
        tx,
        EntityKind.GENERATION,
        actor.accountId(),
        project,
        c.id(),
        new GenerationData(c.id(), null, "QUEUED", null, null, null));
    return run;
  }

  public Entity<?> askPlanning(
      WorkspaceStore.Transaction tx,
      Entity<RunData> run,
      UUID conversation,
      String question,
      List<String> options) {
    if (!run.data().status().equals("PLANNING") || options == null || options.size() != 3)
      throw WorkspaceFailure.invalid("Нужны три варианта уточнения");
    for (String option : options) Records.text(option, "option", 1000);
    var result =
        records.create(
            tx,
            EntityKind.CHECKPOINT,
            run.ownerId(),
            run.projectId(),
            run.id(),
            Map.of(
                "type",
                "question",
                "planning",
                true,
                "question",
                Records.text(question, "question", 2000),
                "options",
                List.copyOf(options),
                "open",
                true,
                "conversationId",
                conversation,
                "revision",
                run.data().requirementsVersion()));
    var d = run.data();
    records.change(
        tx,
        EntityKind.RUN,
        run,
        new RunData(d.goal(), "WAITING", null, d.requirementsVersion(), "user_answer"));
    return result;
  }

  public Entity<PlanData> propose(
      WorkspaceStore.Transaction tx,
      Entity<RunData> run,
      List<PlanStepData> steps,
      List<RequirementData> requirements,
      List<CoverageData> coverage) {
    validate(steps);
    new RequirementCoverage().validate(steps, requirements, coverage);
    if (!run.data().status().equals("PLANNING"))
      throw WorkspaceFailure.conflict("Запуск уже изменился");
    var plan =
        records.create(
            tx,
            EntityKind.PLAN,
            run.ownerId(),
            run.projectId(),
            run.id(),
            new PlanData(
                List.copyOf(steps),
                run.data().requirementsVersion(),
                false,
                List.copyOf(requirements),
                List.copyOf(coverage)));
    var d = run.data();
    records.change(
        tx,
        EntityKind.RUN,
        run,
        new RunData(
            d.goal(), "AWAITING_PLAN", plan.id(), d.requirementsVersion(), "plan_approval"));
    return plan;
  }

  public Entity<RunData> approve(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var run = Records.require(tx, EntityKind.RUN, actor.accountId(), id, RunData.class);
    Records.version(run, version);
    if (!run.data().status().equals("AWAITING_PLAN"))
      throw WorkspaceFailure.invalid("Нет плана для принятия");
    var plan =
        Records.require(
            tx, EntityKind.PLAN, actor.accountId(), run.data().planId(), PlanData.class);
    if (plan.data().requirementsVersion() != run.data().requirementsVersion())
      throw WorkspaceFailure.conflict("План использует старые требования");
    validate(plan.data().steps());
    new RequirementCoverage()
        .validate(plan.data().steps(), plan.data().requirements(), plan.data().coverage());
    var ids = new HashMap<String, UUID>();
    for (var step : plan.data().steps()) ids.put(step.key(), UUID.randomUUID());
    for (var step : plan.data().steps()) {
      UUID taskId = ids.get(step.key());
      var now = run.updatedAt();
      var task =
          new Entity<>(
              taskId,
              actor.accountId(),
              run.projectId(),
              run.id(),
              0,
              now,
              now,
              new TaskData(
                      step.title(),
                      step.criteria(),
                      step.dependencies().stream().map(ids::get).toList(),
                      step.role(),
                      step.paths(),
                      "READY",
                      null,
                      null)
                  .atRevision(run.data().requirementsVersion()));
      tx.insert(EntityKind.TASK, task);
      tx.event(actor.accountId(), run.projectId(), "task.created", Map.of("id", taskId));
    }
    var mapped = new LinkedHashMap<String, List<UUID>>();
    for (var relation : plan.data().coverage())
      mapped.put(relation.requirementKey(), relation.taskKeys().stream().map(ids::get).toList());
    records.create(
        tx,
        EntityKind.CHECKPOINT,
        actor.accountId(),
        run.projectId(),
        run.id(),
        Map.of(
            "type",
            "requirement_coverage",
            "revision",
            run.data().requirementsVersion(),
            "requirements",
            plan.data().requirements(),
            "taskIds",
            mapped));
    records.change(
        tx,
        EntityKind.PLAN,
        plan,
        new PlanData(
            plan.data().steps(),
            plan.data().requirementsVersion(),
            true,
            plan.data().requirements(),
            plan.data().coverage()));
    var d = run.data();
    return records.change(
        tx,
        EntityKind.RUN,
        run,
        new RunData(d.goal(), "RUNNING", d.planId(), d.requirementsVersion(), null));
  }

  public Entity<RunData> control(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version, String action) {
    var e = Records.require(tx, EntityKind.RUN, actor.accountId(), id, RunData.class);
    Records.version(e, version);
    var d = e.data();
    if (Set.of("COMPLETED", "CANCELLED", "FAILED").contains(d.status()))
      throw WorkspaceFailure.invalid("Запуск уже завершён");
    String next =
        switch (action) {
          case "pause" -> "PAUSED";
          case "resume" -> {
            var sessionIds =
                tx
                    .all(
                        EntityKind.AGENT_SESSION,
                        actor.accountId(),
                        e.projectId(),
                        id,
                        AgentSessionData.class)
                    .stream()
                    .map(Entity::id)
                    .collect(java.util.stream.Collectors.toSet());
            if (tx
                .all(
                    EntityKind.TOOL_OPERATION,
                    actor.accountId(),
                    e.projectId(),
                    null,
                    ToolOperationData.class)
                .stream()
                .anyMatch(
                    op ->
                        sessionIds.contains(op.data().sessionId())
                            && Set.of("UNKNOWN", "RUNNING", "RECONCILING")
                                .contains(op.data().status())))
              throw new WorkspaceFailure(
                  409, "operation_unknown", "Сначала определите исход незавершённых операций");
            if ("user_answer".equals(d.waitingReason()))
              throw WorkspaceFailure.invalid("Сначала ответьте на вопрос планирования");
            if (!Set.of("PAUSED", "INTERRUPTED", "WAITING").contains(d.status()))
              throw WorkspaceFailure.invalid("Запуск не приостановлен");
            if (d.planId() == null) yield "PLANNING";
            var plan =
                Records.require(tx, EntityKind.PLAN, actor.accountId(), d.planId(), PlanData.class);
            yield plan.data().approved() ? "RUNNING" : "AWAITING_PLAN";
          }
          case "stop" -> "CANCELLED";
          default -> throw WorkspaceFailure.invalid("Неизвестное действие");
        };
    for (var s :
        tx.list(
            EntityKind.AGENT_SESSION,
            actor.accountId(),
            e.projectId(),
            id,
            AgentSessionData.class,
            10000)) {
      var v = s.data();
      var task =
          Records.require(tx, EntityKind.TASK, actor.accountId(), v.taskId(), TaskData.class);
      if (task.data().revision() != d.requirementsVersion()) continue;
      if (!Set.of("COMPLETED", "FAILED", "CANCELLED").contains(v.status()))
        records.change(
            tx,
            EntityKind.AGENT_SESSION,
            s,
            new AgentSessionData(
                v.role(),
                v.instruction(),
                v.taskId(),
                v.conversationId(),
                v.parentSessionId(),
                v.depth(),
                v.workspace(),
                next.equals("CANCELLED")
                    ? "CANCELLED"
                    : next.equals("PAUSED") ? "PAUSED" : "QUEUED",
                null,
                v.turns()));
    }
    if (action.equals("resume")) {
      for (var g :
          tx.list(
              EntityKind.GENERATION,
              actor.accountId(),
              e.projectId(),
              null,
              GenerationData.class,
              10000)) {
        var v = g.data();
        if (v.sessionId() == null) {
          var conversation =
              Records.require(
                  tx,
                  EntityKind.CONVERSATION,
                  actor.accountId(),
                  v.conversationId(),
                  ConversationData.class);
          if (id.equals(conversation.data().runId())
              && conversation.data().requirementsVersion() == d.requirementsVersion()
              && d.planId() == null
              && Set.of("PAUSED", "INTERRUPTED", "FAILED").contains(v.status()))
            records.change(
                tx,
                EntityKind.GENERATION,
                g,
                new GenerationData(
                    v.conversationId(), null, "QUEUED", null, v.inputTokens(), v.outputTokens()));
          continue;
        }
        var session =
            Records.require(
                tx,
                EntityKind.AGENT_SESSION,
                actor.accountId(),
                v.sessionId(),
                AgentSessionData.class);
        var task =
            Records.require(
                tx, EntityKind.TASK, actor.accountId(), session.data().taskId(), TaskData.class);
        if (session.parentId().equals(id)
            && task.data().revision() == d.requirementsVersion()
            && Set.of("PAUSED", "INTERRUPTED").contains(v.status()))
          records.change(
              tx,
              EntityKind.GENERATION,
              g,
              new GenerationData(
                  v.conversationId(),
                  v.sessionId(),
                  "QUEUED",
                  null,
                  v.inputTokens(),
                  v.outputTokens()));
      }
    }
    return records.change(
        tx,
        EntityKind.RUN,
        e,
        new RunData(d.goal(), next, d.planId(), d.requirementsVersion(), null));
  }

  public Entity<RunData> steer(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version, String goal) {
    var run = control(tx, actor, id, version, "pause");
    String text =
        Records.text(
            run.data().goal()
                + "\nНовое уточнение пользователя:\n"
                + Records.text(goal, "goal", 32000),
            "requirements",
            128000);
    long revision = run.data().requirementsVersion() + 1;
    records.create(
        tx,
        EntityKind.SPECIFICATION,
        actor.accountId(),
        run.projectId(),
        id,
        Map.of("revision", revision, "content", text));
    var d = run.data();
    var changed =
        records.change(
            tx, EntityKind.RUN, run, new RunData(text, "PLANNING", null, revision, null));
    var c =
        records.create(
            tx,
            EntityKind.CONVERSATION,
            actor.accountId(),
            run.projectId(),
            null,
            new ConversationData("Пересмотр плана", "PLAN", id, false).forRequirements(revision));
    conversations.append(
        tx, actor.accountId(), run.projectId(), c.id(), "user", text, null, null, null);
    records.create(
        tx,
        EntityKind.GENERATION,
        actor.accountId(),
        run.projectId(),
        c.id(),
        new GenerationData(c.id(), null, "QUEUED", null, null, null));
    return changed;
  }

  private void validate(List<PlanStepData> steps) {
    if (steps == null || steps.isEmpty() || steps.size() > 50)
      throw WorkspaceFailure.invalid("План должен содержать 1–50 задач");
    var map = new LinkedHashMap<String, PlanStepData>();
    for (var s : steps) {
      Records.text(s.key(), "key", 100);
      Records.text(s.title(), "title", 500);
      if (s.criteria() == null
          || s.criteria().isEmpty()
          || s.dependencies() == null
          || s.paths() == null
          || s.paths().isEmpty())
        throw WorkspaceFailure.invalid("Нужны критерии, зависимости и пути");
      for (String c : s.criteria()) Records.text(c, "criterion", 2000);
      for (String path : s.paths())
        if (!WorkspacePaths.isSafeRelative(path))
          throw WorkspaceFailure.invalid("Неверная область задачи");
      roles.instruction(s.role());
      if (Set.of("REVIEWER", "BUILDER", "SCOUT", "CHECKER").contains(s.role()))
        throw WorkspaceFailure.invalid("Эта роль создаётся сервером для отдельного назначения");
      if (map.putIfAbsent(s.key(), s) != null)
        throw WorkspaceFailure.invalid("Повтор ключа задачи");
    }
    var visited = new HashSet<String>();
    var active = new HashSet<String>();
    for (String key : map.keySet()) visit(key, map, visited, active);
  }

  private void visit(
      String key, Map<String, PlanStepData> steps, Set<String> visited, Set<String> active) {
    if (visited.contains(key)) return;
    if (!steps.containsKey(key) || !active.add(key))
      throw WorkspaceFailure.invalid("Неизвестная или циклическая зависимость");
    for (String dependency : steps.get(key).dependencies())
      visit(dependency, steps, visited, active);
    active.remove(key);
    visited.add(key);
  }
}
