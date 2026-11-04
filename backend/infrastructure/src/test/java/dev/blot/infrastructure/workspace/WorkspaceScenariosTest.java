package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.conversation.ConversationLifecycle;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.conversation.MemoryService;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.application.workspace.execution.GenerationStateService;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.application.workspace.identity.AccountService;
import dev.blot.application.workspace.identity.EmailChallengeService;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.conversation.SummaryData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import dev.blot.infrastructure.workspace.security.ArgonPasswordHasher;
import java.nio.file.Path;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;

class WorkspaceScenariosTest {
  @TempDir Path directory;
  WorkspaceStore store;
  final Clock clock = Clock.fixed(Instant.parse("2026-10-21T00:00:00Z"), ZoneOffset.UTC);
  Records records;
  AccountService accounts;
  SessionService sessions;
  final Map<String, String> mail = new HashMap<>();

  @BeforeEach
  void prepare() {
    var json = new JacksonCodec();
    store = new SqliteWorkspaceStore(directory.resolve("test.db"), json, clock);
    records = new Records(clock);
    var hasher = new ArgonPasswordHasher();
    var tokens = new TokenGenerator();
    var challenge =
        new EmailChallengeService(
            store,
            (email, code, purpose) -> mail.put(email + ":" + purpose, code),
            hasher,
            clock,
            records,
            tokens);
    accounts = new AccountService(store, hasher, challenge, records, clock);
    sessions = new SessionService(store, tokens, records, clock);
  }

  Actor register(String email) {
    accounts.registerAccount(email, "correct horse battery", "Test");
    accounts.verifyEmail(email, mail.get(email + ":verify"));
    var account = accounts.credentials(email, "correct horse battery");
    return sessions.authenticate(sessions.create(account.id(), null, true).token(), true);
  }

  @Test
  void verificationSessionsAndResetAreReal() {
    accounts.registerAccount("person@example.com", "correct horse battery", "Person");
    assertEquals(
        "email_unverified",
        assertThrows(
                WorkspaceFailure.class,
                () -> accounts.credentials("person@example.com", "correct horse battery"))
            .code());
    assertThrows(WorkspaceFailure.class, () -> accounts.verifyEmail("person@example.com", "wrong"));
    accounts.verifyEmail("person@example.com", mail.get("person@example.com:verify"));
    var user = accounts.credentials("person@example.com", "correct horse battery");
    var token = sessions.create(user.id(), null, true).token();
    assertEquals(user.id(), sessions.authenticate(token, true).accountId());
    assertThrows(WorkspaceFailure.class, () -> sessions.authenticate(token, false));
    accounts.requestReset("person@example.com");
    accounts.reset(
        "person@example.com", mail.get("person@example.com:reset"), "new correct password");
    assertThrows(WorkspaceFailure.class, () -> sessions.authenticate(token, true));
    assertNotNull(accounts.credentials("person@example.com", "new correct password"));
  }

  @Test
  void invalidCodeAttemptsRemainCommitted() {
    accounts.registerAccount("person@example.com", "correct horse battery", "Person");
    for (int i = 0; i < 5; i++)
      assertThrows(
          WorkspaceFailure.class, () -> accounts.verifyEmail("person@example.com", "not-a-code"));
    assertThrows(
        WorkspaceFailure.class,
        () -> accounts.verifyEmail("person@example.com", mail.get("person@example.com:verify")));
  }

  @Test
  void commandRetryReturnsSameReceiptAndRollsBackFailure() {
    Actor actor = register("a@example.com");
    var dispatcher = new CommandDispatcher(store, new JacksonCodec(), new TokenGenerator());
    var chat = new ConversationService(records);
    dispatcher.register(
        "chat.create", (tx, a, c) -> chat.create(tx, a, null, (String) c.payload().get("title")));
    UUID id = UUID.randomUUID();
    var command =
        new CommandDispatcher.Command(2, id, "chat.create", null, null, Map.of("title", "Hello"));
    var first = dispatcher.execute(actor, command);
    var retry = dispatcher.execute(actor, command);
    assertEquals(first.operationId(), retry.operationId());
    assertEquals(
        1,
        store
            .transact(
                tx ->
                    tx.list(
                        EntityKind.CONVERSATION,
                        actor.accountId(),
                        null,
                        null,
                        ConversationData.class,
                        100))
            .size());
    assertEquals(
        "duplicate_command_mismatch",
        assertThrows(
                WorkspaceFailure.class,
                () ->
                    dispatcher.execute(
                        actor,
                        new CommandDispatcher.Command(
                            2, id, "chat.create", null, null, Map.of("title", "Changed"))))
            .code());
    dispatcher.register(
        "broken",
        (tx, a, c) -> {
          chat.create(tx, a, null, "Rolled back");
          throw WorkspaceFailure.invalid("fail");
        });
    assertThrows(
        WorkspaceFailure.class,
        () ->
            dispatcher.execute(
                actor,
                new CommandDispatcher.Command(
                    2, UUID.randomUUID(), "broken", null, null, Map.of())));
    assertEquals(
        1,
        store
            .transact(
                tx ->
                    tx.list(
                        EntityKind.CONVERSATION,
                        actor.accountId(),
                        null,
                        null,
                        ConversationData.class,
                        100))
            .size());
  }

  @Test
  void memoryAndEventsAreIsolatedByOwner() {
    Actor a = register("a@example.com"), b = register("b@example.com");
    var memory = new MemoryService(store, records);
    var entry =
        store.transact(
            tx ->
                memory.save(
                    tx,
                    a,
                    null,
                    null,
                    null,
                    new MemoryData("user", null, "Предпочитаю Kotlin и Swift", null, "active")));
    assertEquals(1, memory.search(a.accountId(), null, null, "Swift").size());
    assertTrue(memory.search(b.accountId(), null, null, "Swift").isEmpty());
    assertTrue(
        store
            .transact(tx -> tx.find(EntityKind.MEMORY, b.accountId(), entry.id(), MemoryData.class))
            .isEmpty());
    store.transact(
        tx -> {
          memory.delete(tx, a, entry.id(), entry.version());
          return null;
        });
    assertTrue(memory.search(a.accountId(), null, null, "Swift").isEmpty());
    assertTrue(
        store.transact(tx -> tx.events(b.accountId(), 0, 100)).stream()
            .noneMatch(e -> e.ownerId().equals(a.accountId())));
  }

  @Test
  void grantIsConsumedOnceAndVersionConflictsDoNotOverwrite() {
    Actor actor = register("a@example.com");
    var permission =
        new PermissionService(records, new JacksonCodec(), new TokenGenerator(), clock);
    var action =
        store.transact(
            tx ->
                permission.prepare(
                    tx,
                    actor.accountId(),
                    null,
                    UUID.randomUUID(),
                    UUID.randomUUID(),
                    "patch.apply",
                    "sha",
                    Map.of("path", "a.txt")));
    store.transact(tx -> permission.grant(tx, actor, action.id(), 0L, 60, 1));
    assertThrows(
        WorkspaceFailure.class,
        () -> store.transact(tx -> permission.grant(tx, actor, action.id(), 0L, 60, 1)));
    store.transact(
        tx -> {
          permission.consume(tx, actor.accountId(), action);
          return null;
        });
    assertEquals(
        "permission_required",
        assertThrows(
                WorkspaceFailure.class,
                () ->
                    store.transact(
                        tx -> {
                          permission.consume(tx, actor.accountId(), action);
                          return null;
                        }))
            .code());
  }

  @Test
  void keysetPageDoesNotSkipRecordsAfterEarlierDeletion() {
    Actor actor = register("page@example.com");
    var chat = new ConversationService(records);
    store.transact(
        tx -> {
          for (int n = 0; n < 3; n++) chat.create(tx, actor, null, "Chat " + n);
          return null;
        });
    var first =
        store.transact(
            tx ->
                tx.page(
                    EntityKind.CONVERSATION,
                    actor.accountId(),
                    null,
                    null,
                    ConversationData.class,
                    2,
                    0));
    store.transact(
        tx -> {
          tx.delete(EntityKind.CONVERSATION, actor.accountId(), first.getFirst().id());
          return null;
        });
    var cursor = first.getLast();
    var next =
        store.transact(
            tx ->
                tx.after(
                    EntityKind.CONVERSATION,
                    actor.accountId(),
                    null,
                    null,
                    ConversationData.class,
                    2,
                    cursor.createdAt(),
                    cursor.id()));
    assertEquals(1, next.size());
    assertFalse(first.stream().anyMatch(row -> row.id().equals(next.getFirst().id())));
  }

  @Test
  void deletingSourceInvalidatesSummaryAndStopsUsingDerivedFact() {
    var actor = register("history@example.com");
    var chat = new ConversationService(records);
    var memory = new MemoryService(store, records);
    var lifecycle = new ConversationLifecycle(records, memory);
    var conversation = store.transact(tx -> chat.create(tx, actor, null, "History"));
    var message =
        store.transact(
            tx ->
                chat.append(
                    tx,
                    actor.accountId(),
                    null,
                    conversation.id(),
                    "user",
                    "Swift preference",
                    null,
                    null,
                    null));
    var fact =
        store.transact(
            tx ->
                memory.save(
                    tx,
                    actor,
                    null,
                    null,
                    null,
                    new MemoryData("user", null, "Swift preference", message.id(), "active")));
    store.transact(
        tx ->
            records.create(
                tx,
                EntityKind.SUMMARY,
                actor.accountId(),
                null,
                conversation.id(),
                new SummaryData(
                    conversation.id(),
                    message.data().ordinal(),
                    "Swift preference",
                    List.of(fact.id()),
                    true)));
    store.transact(
        tx -> {
          lifecycle.deleteMessage(tx, actor, message.id(), message.version());
          return null;
        });
    assertTrue(
        store
            .transact(
                tx ->
                    tx.find(EntityKind.MESSAGE, actor.accountId(), message.id(), MessageData.class))
            .isEmpty());
    assertTrue(
        store.transact(tx -> tx.latestSummary(actor.accountId(), conversation.id())).isEmpty());
    assertTrue(memory.search(actor.accountId(), null, null, "Swift").isEmpty());
    var stale =
        store.transact(
            tx ->
                Records.require(
                    tx, EntityKind.MEMORY, actor.accountId(), fact.id(), MemoryData.class));
    assertEquals("stale", stale.data().status());
    assertNull(stale.data().sourceId());
  }

  @Test
  void failedPlanningWaitsAndCanResumeAfterConfigurationIsFixed() {
    var actor = register("plan@example.com");
    var chat = new ConversationService(records);
    var runs = new RunService(records, chat, new RoleCatalog());
    var project =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.PROJECT,
                    actor.accountId(),
                    null,
                    null,
                    new ProjectData("Project", directory.toString(), "base", "main", false)));
    var run = store.transact(tx -> runs.create(tx, actor, project.id(), "Implement goal"));
    var generation =
        store
            .transact(
                tx ->
                    tx.all(
                        EntityKind.GENERATION,
                        actor.accountId(),
                        project.id(),
                        null,
                        GenerationData.class))
            .getFirst();
    new GenerationStateService(store, records)
        .finish(generation, "FAILED", "provider_unconfigured", null);
    var waiting =
        store.transact(
            tx -> Records.require(tx, EntityKind.RUN, actor.accountId(), run.id(), RunData.class));
    assertEquals("WAITING", waiting.data().status());
    var resumed =
        store.transact(tx -> runs.control(tx, actor, run.id(), waiting.version(), "resume"));
    assertEquals("PLANNING", resumed.data().status());
    assertEquals(
        "QUEUED",
        store
            .transact(
                tx ->
                    Records.require(
                        tx,
                        EntityKind.GENERATION,
                        actor.accountId(),
                        generation.id(),
                        GenerationData.class))
            .data()
            .status());
  }

  @Test
  void commandReadPreparationRunsBeforeTransactionAndIsSkippedOnRetry() {
    var actor = register("prepared@example.com");
    var inside = new java.util.concurrent.atomic.AtomicBoolean();
    WorkspaceStore monitored =
        new WorkspaceStore() {
          public <T> T transact(
              java.util.function.Function<WorkspaceStore.Transaction, T> operation) {
            return store.transact(
                tx -> {
                  inside.set(true);
                  try {
                    return operation.apply(tx);
                  } finally {
                    inside.set(false);
                  }
                });
          }
        };
    var dispatcher = new CommandDispatcher(monitored, new JacksonCodec(), new TokenGenerator());
    var preparations = new java.util.concurrent.atomic.AtomicInteger();
    dispatcher.registerPrepared(
        "prepared",
        (sender, command) -> {
          assertFalse(inside.get());
          preparations.incrementAndGet();
          return (tx, current, original) -> {
            assertTrue(inside.get());
            return Map.of("done", true);
          };
        });
    var command =
        new CommandDispatcher.Command(2, UUID.randomUUID(), "prepared", null, null, Map.of());
    assertEquals(dispatcher.execute(actor, command), dispatcher.execute(actor, command));
    assertEquals(1, preparations.get());
  }
}
