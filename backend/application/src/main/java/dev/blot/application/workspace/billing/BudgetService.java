package dev.blot.application.workspace.billing;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.billing.BudgetData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.identity.Actor;
import java.util.*;

public final class BudgetService {
  private final WorkspaceStore store;
  private final Records records;

  public BudgetService(WorkspaceStore store, Records records) {
    this.store = store;
    this.records = records;
  }

  public record Reservation(UUID id, long amount) {}

  public List<Reservation> reserve(
      dev.blot.application.ports.ProviderGateway.Request request, long amount, long limit) {
    return store.transact(
        tx -> {
          var scopes = new java.util.ArrayList<UUID>();
          scopes.add(null);
          if (request.projectId() != null) scopes.add(request.projectId());
          if (request.runId() != null) scopes.add(request.runId());
          if (request.sessionId() != null) scopes.add(request.sessionId());
          var result = new java.util.ArrayList<Reservation>();
          for (UUID scope : scopes) {
            long cap =
                scope == null
                    ? Math.multiplyExact(limit, 10)
                    : scope.equals(request.projectId()) ? Math.multiplyExact(limit, 4) : limit;
            var budget =
                tx.all(EntityKind.BUDGET, request.ownerId(), null, null, BudgetData.class).stream()
                    .filter(e -> java.util.Objects.equals(scope, e.parentId()))
                    .findFirst()
                    .orElseGet(
                        () ->
                            records.create(
                                tx,
                                EntityKind.BUDGET,
                                request.ownerId(),
                                scope == null ? null : request.projectId(),
                                scope,
                                new BudgetData(cap, 0, 0, false)));
            var d = budget.data();
            if (amount < 0 || amount > d.limit() - d.spent() - d.reserved())
              throw new WorkspaceFailure(429, "budget_exceeded", "Лимит токенов исчерпан");
            records.change(
                tx,
                EntityKind.BUDGET,
                budget,
                new BudgetData(d.limit(), d.reserved() + amount, d.spent(), d.usageUnknown()));
            result.add(new Reservation(budget.id(), amount));
          }
          return java.util.List.copyOf(result);
        });
  }

  public void settle(UUID owner, List<Reservation> reservations, Long actual) {
    store.transact(
        tx -> {
          for (var reservation : reservations) {
            var b =
                Records.require(tx, EntityKind.BUDGET, owner, reservation.id(), BudgetData.class);
            var d = b.data();
            records.change(
                tx,
                EntityKind.BUDGET,
                b,
                new BudgetData(
                    d.limit(),
                    Math.max(0, d.reserved() - reservation.amount()),
                    d.spent() + (actual == null ? reservation.amount() : actual),
                    d.usageUnknown() || actual == null));
          }
          return null;
        });
  }

  public void recover() {
    store.transact(
        tx -> {
          for (var budget : tx.reservedBudgets(BudgetData.class, 10000)) {
            var d = budget.data();
            if (d.reserved() > 0)
              records.change(
                  tx,
                  EntityKind.BUDGET,
                  budget,
                  new BudgetData(d.limit(), 0, d.spent() + d.reserved(), true));
          }
          return null;
        });
  }

  public Entity<BudgetData> increase(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version, long limit) {
    var b = Records.require(tx, EntityKind.BUDGET, actor.accountId(), id, BudgetData.class);
    Records.version(b, version);
    var d = b.data();
    if (limit < d.spent() + d.reserved())
      throw WorkspaceFailure.invalid("Лимит меньше уже учтённого расхода");
    var changed =
        records.change(
            tx,
            EntityKind.BUDGET,
            b,
            new BudgetData(limit, d.reserved(), d.spent(), d.usageUnknown()));
    for (var generation :
        tx.all(EntityKind.GENERATION, actor.accountId(), null, null, GenerationData.class)) {
      var state = generation.data();
      if (state.status().equals("BLOCKED") && "budget_exceeded".equals(state.error()))
        records.change(
            tx,
            EntityKind.GENERATION,
            generation,
            new GenerationData(
                state.conversationId(),
                state.sessionId(),
                "QUEUED",
                null,
                state.inputTokens(),
                state.outputTokens()));
    }
    return changed;
  }
}
