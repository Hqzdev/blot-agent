package dev.blot.infrastructure.workspace;

import dev.blot.application.ports.*;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.ProcessGateway;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.agent.AgentCommunicationTools;
import dev.blot.application.workspace.agent.AgentExecutionService;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.agent.AgentResultService;
import dev.blot.application.workspace.agent.DelegationService;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.conversation.ContextBuilder;
import dev.blot.application.workspace.conversation.ContextCompactor;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.conversation.MemoryService;
import dev.blot.application.workspace.execution.GenerationStateService;
import dev.blot.application.workspace.execution.GenerationWorker;
import dev.blot.application.workspace.execution.PreparedActionExecutor;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.application.workspace.execution.ToolHistory;
import dev.blot.application.workspace.execution.ToolService;
import dev.blot.application.workspace.execution.WorkflowScheduler;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.integrations.IntegrationService;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.application.workspace.profile.ProfileService;
import dev.blot.application.workspace.providers.ModelStreamingService;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.application.workspace.review.ReviewService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.ReviewData;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.agent.AttemptData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import dev.blot.infrastructure.workspace.artifacts.LocalArtifactStore;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.function.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class AgentWorkflowTest {
  @TempDir Path directory;

  @Test
  void planAuthorToolApprovalReviewIntegrationAndFinalChecks() throws Exception {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("state.db"), json, clock);
    var records = new Records(clock);
    var tokens = new TokenGenerator();
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
                  clock.instant(),
                  clock.instant(),
                  new AccountData("owner@example.com", "hash", true, "Owner")));
          return null;
        });
    var fakeGit =
        new GitGateway() {
          public Remote remote(Path p, String name) {
            throw new AssertionError("Unexpected remote");
          }

          public String remoteHead(Path p, String name, String ref) {
            throw new AssertionError("Unexpected remote");
          }

          public Repository inspect(Path root) {
            return new Repository("base", "main", false);
          }

          public Path createWorkspace(Path repo, UUID run, UUID session) {
            try {
              Path path = directory.resolve(session.toString());
              Files.createDirectories(path);
              Files.writeString(path.resolve("source.txt"), "Source");
              return path;
            } catch (Exception e) {
              throw new RuntimeException(e);
            }
          }

          public String snapshot(Path root) {
            return "";
          }

          public void integrate(Path root, String patch) {}

          public String commit(Path p, String b, String h, String m) {
            throw new AssertionError("Unexpected commit");
          }

          public String push(Path p, String r, String f, String expectedCommit) {
            throw new AssertionError("Unexpected push");
          }
        };
    var chat = new ConversationService(records);
    var settings = new ProviderSettingsService(store, records);
    var roles = new RoleCatalog();
    var runs = new RunService(records, chat, roles);
    var permissions = new PermissionService(records, json, tokens, clock);
    var artifactStore = new LocalArtifactStore(directory.resolve("artifacts"));
    var integration = new IntegrationService(store, records);
    var profiles = new ProfileService(store, records, roles, new ToolDefinitions());
    var scheduler =
        new WorkflowScheduler(store, records, chat, fakeGit, profiles, integration, artifactStore);
    var delegation = new DelegationService(store, records);
    var files = new AgentFiles(store, tokens, artifactStore, records);
    ProcessGateway process =
        (path, scopes, program, args, timeout, cancelled) ->
            new ProcessGateway.Result(0, "Tests passed", false);
    var actions =
        new PreparedActionExecutor(
            store, records, permissions, fakeGit, process, artifactStore, tokens, files);
    var tools =
        new ToolService(
            store,
            permissions,
            fakeGit,
            json,
            tokens,
            delegation,
            new ToolDefinitions(),
            files,
            actions,
            new AgentCommunicationTools(store, records));
    var model =
        new ProviderGateway() {
          public List<String> models(UUID o) {
            return List.of("test");
          }

          public long countTokens(UUID o, String m, String text) {
            return Math.max(1, text.length() / 4);
          }

          public Reply generate(
              Request request, Consumer<String> output, BooleanSupplier cancelled) {
            String instruction = request.messages().getFirst().content();
            if (instruction.contains("Ты планировщик"))
              return reply(
                  "{\"requirements\":[{\"key\":\"r1\",\"content\":\"Correct result\"}],\"coverage\":[{\"requirementKey\":\"r1\",\"taskKeys\":[\"a\"]}],\"steps\":[{\"key\":\"a\",\"title\":\"Fix a thing\",\"criteria\":[\"Correct result\"],\"dependencies\":[],\"role\":\"BACKEND\",\"paths\":[\".\"]}]}");
            if (instruction.contains("Верни JSON"))
              return reply("{\"decision\":\"accepted\",\"findings\":[]}");
            if (instruction.contains("Проверить безопасность итоговой версии")
                && request.messages().stream()
                    .noneMatch(
                        m -> m.role().equals("function") && "project_read_file".equals(m.name())))
              return call("project_read_file", Map.of("path", "source.txt"));
            if (instruction.contains("Проверить итоговую версию")
                && request.messages().stream()
                    .noneMatch(
                        m -> m.role().equals("function") && m.content().contains("exitCode")))
              return call(
                  "process_run",
                  Map.of("program", "swift", "arguments", List.of("test"), "timeoutSeconds", 30));
            output.accept("Done with evidence");
            return reply("Done with evidence");
          }

          private Reply reply(String text) {
            return new Reply(text, List.of(), 10L, 5L);
          }

          private Reply call(String name, Object args) {
            return new Reply("", List.of(new ToolCall(name, args, "state")), 10L, 5L);
          }
        };
    var memory = new MemoryService(store, records);
    var context =
        new ContextBuilder(store, model, memory, records, new ContextCompactor(model, json), json);
    var reviews = new ReviewService(records);
    var project =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.PROJECT,
                    owner,
                    null,
                    null,
                    new ProjectData("Test", directory.toString(), "base", "main", false)));
    store.transact(
        tx ->
            settings.save(tx, actor, new ProviderSettingsData("test", 32768, 4096, 1000000), null));
    var streaming = new ModelStreamingService(store, records, model, chat);
    var results =
        new AgentResultService(store, records, reviews, fakeGit, artifactStore, scheduler, json);
    var agents =
        new AgentExecutionService(
            store,
            records,
            chat,
            context,
            streaming,
            tools,
            results,
            profiles,
            new ToolHistory(store, chat, tools, json));
    try (var worker =
        new GenerationWorker(
            store,
            records,
            settings,
            context,
            runs,
            scheduler,
            json,
            streaming,
            agents,
            new GenerationStateService(store, records))) {
      worker.start();
      var run = store.transact(tx -> runs.create(tx, actor, project.id(), "Fix it"));
      await(() -> read(store, owner, run.id()).data().status().equals("AWAITING_PLAN"));
      var planned = read(store, owner, run.id());
      store.transact(tx -> runs.approve(tx, actor, run.id(), planned.version()));
      await(
          () ->
              !store
                  .transact(
                      tx ->
                          tx.list(
                              EntityKind.PREPARED_ACTION,
                              owner,
                              project.id(),
                              null,
                              PreparedActionData.class,
                              100))
                  .isEmpty());
      for (var action :
          store.transact(
              tx ->
                  tx.list(
                      EntityKind.PREPARED_ACTION,
                      owner,
                      project.id(),
                      null,
                      PreparedActionData.class,
                      100))) {
        store.transact(tx -> permissions.grant(tx, actor, action.id(), action.version(), 60, 1));
        var session =
            store.transact(
                tx ->
                    Records.require(
                        tx,
                        EntityKind.AGENT_SESSION,
                        owner,
                        action.data().sessionId(),
                        AgentSessionData.class));
        store.transact(
            tx -> {
              for (var job :
                  tx.list(
                      EntityKind.GENERATION,
                      owner,
                      null,
                      session.data().conversationId(),
                      GenerationData.class,
                      100)) {
                var d = job.data();
                if (d.status().equals("BLOCKED"))
                  records.change(
                      tx,
                      EntityKind.GENERATION,
                      job,
                      new GenerationData(
                          d.conversationId(), d.sessionId(), "QUEUED", null, null, null));
              }
              return null;
            });
      }
      try {
        await(() -> read(store, owner, run.id()).data().status().equals("READY_FOR_ACCEPTANCE"));
      } catch (AssertionError error) {
        String diagnostics =
            store.transact(
                tx ->
                    java.util.List.of(
                            EntityKind.RUN,
                            EntityKind.TASK,
                            EntityKind.GENERATION,
                            EntityKind.TOOL_OPERATION,
                            EntityKind.GRANT)
                        .stream()
                        .map(k -> k + ":" + tx.list(k, owner, null, null, Object.class, 100))
                        .collect(java.util.stream.Collectors.joining("\n")));
        fail(diagnostics, error);
      }
      var ready = read(store, owner, run.id());
      var completed =
          store.transact(tx -> integration.accept(tx, actor, run.id(), ready.version()));
      assertEquals("COMPLETED", completed.data().status());
      assertTrue(
          store
                  .transact(
                      tx ->
                          tx.list(
                              EntityKind.REVIEW, owner, project.id(), null, ReviewData.class, 100))
                  .size()
              >= 4);
      assertTrue(
          store
              .transact(
                  tx ->
                      tx.list(
                          EntityKind.TASK_ATTEMPT,
                          owner,
                          project.id(),
                          null,
                          AttemptData.class,
                          100))
              .stream()
              .allMatch(e -> e.data().status().equals("ACCEPTED")));
    }
  }

  private static Entity<RunData> read(WorkspaceStore store, UUID owner, UUID id) {
    return store.transact(tx -> Records.require(tx, EntityKind.RUN, owner, id, RunData.class));
  }

  private static void await(BooleanSupplier condition) throws Exception {
    long until = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(20);
    while (!condition.getAsBoolean()) {
      if (System.nanoTime() > until) fail("Timed out waiting for workflow");
      Thread.sleep(50);
    }
  }
}
