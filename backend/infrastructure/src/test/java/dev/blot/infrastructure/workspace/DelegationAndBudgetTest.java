package dev.blot.infrastructure.workspace;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.DelegationService;
import dev.blot.application.workspace.billing.BudgetService;
import dev.blot.application.workspace.execution.GenerationStateService;
import dev.blot.core.Project;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.billing.BudgetData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.projects.TaskData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class DelegationAndBudgetTest {
  @TempDir Path directory;

  @Test
  void motesKeepScopeDepthAndParentBudget() {
    var store =
        new SqliteWorkspaceStore(
            directory.resolve("data.db"), new JacksonCodec(), Clock.systemUTC());
    var records = new Records(Clock.systemUTC());
    UUID owner = UUID.randomUUID();
    var actor = new Actor(owner, null, null, true);
    store.transact(
        tx -> {
          tx.insert(
              EntityKind.ACCOUNT,
              new Entity<>(
                  owner,
                  owner,
                  null,
                  null,
                  0,
                  Instant.now(),
                  Instant.now(),
                  new AccountData("owner@example.com", "hash", true, "Owner")));
          return null;
        });
    var project =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.PROJECT,
                    owner,
                    null,
                    null,
                    new ProjectData("Project", directory.toString(), "base", "main", false)));
    var run =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.RUN,
                    owner,
                    project.id(),
                    null,
                    new RunData("Goal", "RUNNING", null, 1, null)));
    var task =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.TASK,
                    owner,
                    project.id(),
                    run.id(),
                    new TaskData(
                        "Main",
                        List.of("Result"),
                        List.of(),
                        "BACKEND",
                        List.of("src"),
                        "RUNNING",
                        null,
                        null)));
    var parent =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.AGENT_SESSION,
                    owner,
                    project.id(),
                    run.id(),
                    new AgentSessionData(
                        "BACKEND",
                        "Instruction",
                        task.id(),
                        UUID.randomUUID(),
                        null,
                        0,
                        directory.toString(),
                        "RUNNING",
                        null,
                        0)));
    var delegation = new DelegationService(store, records);
    var child =
        delegation.spawn(
            parent, "Narrow work", List.of("Small result"), "BUILDER", List.of("src/module"));
    assertEquals(parent.id(), child.data().parentSessionId());
    assertEquals(
        child.id(),
        delegation
            .spawn(parent, "Narrow work", List.of("Small result"), "BUILDER", List.of("src/module"))
            .id());
    assertThrows(
        WorkspaceFailure.class,
        () -> delegation.spawn(parent, "Escape", List.of("Wrong"), "SCOUT", List.of("../secret")));
    var childSession =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.AGENT_SESSION,
                    owner,
                    project.id(),
                    run.id(),
                    new AgentSessionData(
                        "BUILDER",
                        "Instruction",
                        child.id(),
                        UUID.randomUUID(),
                        parent.id(),
                        1,
                        directory.toString(),
                        "RUNNING",
                        null,
                        0)));
    assertThrows(
        WorkspaceFailure.class,
        () ->
            delegation.spawn(
                childSession, "Nested", List.of("Wrong"), "SCOUT", List.of("src/module")));
    var budgets = new BudgetService(store, records);
    var request =
        new ProviderGateway.Request(
            owner, "test", List.of(), List.of(), 100, project.id(), run.id(), childSession.id());
    var reservations = budgets.reserve(request, 1200, 10000);
    assertEquals(4, reservations.size());
    var runBudget =
        store
            .transact(
                tx ->
                    tx.list(EntityKind.BUDGET, owner, project.id(), run.id(), BudgetData.class, 1))
            .getFirst();
    assertEquals(1200, runBudget.data().reserved());
    budgets.recover();
    var recovered =
        store.transact(
            tx -> Records.require(tx, EntityKind.BUDGET, owner, runBudget.id(), BudgetData.class));
    assertEquals(0, recovered.data().reserved());
    assertEquals(1200, recovered.data().spent());
    assertTrue(recovered.data().usageUnknown());
    var waiting =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.GENERATION,
                    owner,
                    project.id(),
                    UUID.randomUUID(),
                    new GenerationData(
                        UUID.randomUUID(), null, "BLOCKED", "budget_exceeded", null, null)));
    store.transact(tx -> budgets.increase(tx, actor, recovered.id(), recovered.version(), 20000));
    assertEquals(
        "QUEUED",
        store
            .transact(
                tx ->
                    Records.require(
                        tx, EntityKind.GENERATION, owner, waiting.id(), GenerationData.class))
            .data()
            .status());
    var generation =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.GENERATION,
                    owner,
                    project.id(),
                    childSession.data().conversationId(),
                    new GenerationData(
                        childSession.data().conversationId(),
                        childSession.id(),
                        "RUNNING",
                        null,
                        null,
                        null)));
    var states = new GenerationStateService(store, records);
    assertFalse(states.cancelled(generation));
    store.transact(
        tx -> {
          var d = parent.data();
          records.change(
              tx,
              EntityKind.AGENT_SESSION,
              parent,
              new AgentSessionData(
                  d.role(),
                  d.instruction(),
                  d.taskId(),
                  d.conversationId(),
                  d.parentSessionId(),
                  d.depth(),
                  d.workspace(),
                  "CANCELLED",
                  "cancelled",
                  d.turns()));
          return null;
        });
    assertTrue(states.cancelled(generation));
  }
}
