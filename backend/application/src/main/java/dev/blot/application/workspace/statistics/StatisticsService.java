package dev.blot.application.workspace.statistics;

import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.ReviewData;
import dev.blot.core.workspace.billing.BudgetData;
import dev.blot.core.workspace.execution.ModelRequestData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import java.util.*;

/** Статистика строится по сохранённым результатам, без выдуманной цены неизвестного usage. */
public final class StatisticsService {
  public record Statistics(
      long knownInputTokens,
      long knownOutputTokens,
      long requestsWithUnknownUsage,
      boolean usageIncomplete,
      long queuedRequests,
      long activeRequests,
      Map<String, Long> runsByStatus,
      Map<String, Long> tasksByStatus,
      long reviews,
      long findings,
      Long costMinorUnits,
      String currency) {}

  private final WorkspaceStore store;

  public StatisticsService(WorkspaceStore store) {
    this.store = store;
  }

  public Statistics read(Actor actor, UUID projectId) {
    return store.transact(
        tx -> {
          if (projectId != null)
            Records.require(
                tx, EntityKind.PROJECT, actor.accountId(), projectId, ProjectData.class);
          long input = 0;
          long output = 0;
          long unknown = 0;
          long queued = 0;
          long active = 0;
          for (var request :
              tx.all(
                  EntityKind.MODEL_REQUEST,
                  actor.accountId(),
                  projectId,
                  null,
                  ModelRequestData.class)) {
            var data = request.data();
            if (data.inputTokens() != null) input += data.inputTokens();
            if (data.outputTokens() != null) output += data.outputTokens();
            if (data.status().equals("QUEUED")) queued++;
            else if (data.status().equals("RUNNING")) active++;
            else if (data.inputTokens() == null || data.outputTokens() == null) unknown++;
          }
          var runs = new TreeMap<String, Long>();
          for (var run : tx.all(EntityKind.RUN, actor.accountId(), projectId, null, RunData.class))
            runs.merge(run.data().status(), 1L, Long::sum);
          var tasks = new TreeMap<String, Long>();
          for (var task :
              tx.all(EntityKind.TASK, actor.accountId(), projectId, null, TaskData.class))
            tasks.merge(task.data().status(), 1L, Long::sum);
          var reviews =
              tx.all(EntityKind.REVIEW, actor.accountId(), projectId, null, ReviewData.class);
          long findings = 0;
          for (var review : reviews) findings += review.data().findings().size();
          boolean incomplete = unknown > 0;
          for (var budget :
              tx.all(EntityKind.BUDGET, actor.accountId(), projectId, null, BudgetData.class))
            incomplete = incomplete || budget.data().usageUnknown();
          return new Statistics(
              input,
              output,
              unknown,
              incomplete,
              queued,
              active,
              Map.copyOf(runs),
              Map.copyOf(tasks),
              reviews.size(),
              findings,
              null,
              null);
        });
  }
}
