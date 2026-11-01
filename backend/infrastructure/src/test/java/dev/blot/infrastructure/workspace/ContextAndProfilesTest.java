package dev.blot.infrastructure.workspace;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.conversation.ContextBuilder;
import dev.blot.application.workspace.conversation.ContextCompactor;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.conversation.MemoryService;
import dev.blot.application.workspace.profile.ProfileService;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.profile.ProfileData;
import dev.blot.core.workspace.provider.ProviderSettingsData;
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

class ContextAndProfilesTest {
  @TempDir Path directory;

  @Test
  void repositoryFreeProjectsCarryMaterialsIntoChatWithoutKeywordMatching() {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("projects.db"), json, clock);
    var records = new Records(clock);
    var actor = account(store, records);
    var projects = new dev.blot.application.workspace.projects.ProjectService(
        null, records, path -> { throw new AssertionError("A chat project must not request folder access"); });
    var project = store.transact(tx -> projects.create(tx, actor, "Launch", null));
    assertEquals("", project.data().repositoryPath());
    assertThrows(WorkspaceFailure.class, () -> projects.inspect(actor, "  ", null));
    assertThrows(WorkspaceFailure.class, () -> projects.inspect(
        new Actor(actor.accountId(), null, UUID.randomUUID(), false), "Remote", null));
    var memory = new MemoryService(store, records);
    store.transact(tx -> memory.save(tx, actor, project.id(), null, null,
        new MemoryData("project", null, "Launch date: December 15", null, "active")));
    var chat = new ConversationService(records);
    var conversation = store.transact(tx -> chat.create(tx, actor, project.id(), "Help"));
    var standalone = store.transact(tx -> chat.create(tx, actor, null, "Help"));
    store.transact(tx -> chat.sendMessage(tx, actor, conversation.id(), "What should we do next?"));
    var provider = new ProviderGateway() {
      public List<String> models(UUID owner) { return List.of("test"); }
      public long countTokens(UUID owner, String model, String text) { return text.length() / 4 + 1; }
      public Reply generate(Request request, Consumer<String> text, BooleanSupplier cancelled) {
        throw new AssertionError("Short history does not require compaction");
      }
    };
    var builder = new ContextBuilder(store, provider, memory, records,
        new ContextCompactor(provider, json), json);
    var settings = new ProviderSettingsData("test", 32768, 4096, 100000);
    assertTrue(builder.build(conversation, settings, "Rules", List.of()).getFirst()
        .content().contains("December 15"));
    assertFalse(builder.build(standalone, settings, "Rules", List.of()).getFirst()
        .content().contains("December 15"));
    var runs = new dev.blot.application.workspace.execution.RunService(records, chat, new RoleCatalog());
    assertThrows(WorkspaceFailure.class, () -> store.transact(
        tx -> runs.create(tx, actor, project.id(), "Change code")));
    assertTrue(store.transact(tx -> tx.all(EntityKind.RUN, actor.accountId(), project.id(), null,
        dev.blot.core.workspace.projects.RunData.class)).isEmpty());
  }

  @Test
  void compactsClosedHistoryToTargetAndRetainsOriginals() {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("data.db"), json, clock);
    var records = new Records(clock);
    var actor = account(store, records);
    var conversations = new ConversationService(records);
    var conversation =
        store.transact(tx -> conversations.create(tx, actor, null, "Long conversation"));
    store.transact(
        tx -> {
          for (int n = 0; n < 40; n++)
            conversations.append(
                tx,
                actor.accountId(),
                null,
                conversation.id(),
                n % 2 == 0 ? "user" : "assistant",
                "message-" + n + " " + "source data ".repeat(50),
                null,
                null,
                null);
          return null;
        });
    var provider =
        new ProviderGateway() {
          public List<String> models(UUID owner) {
            return List.of("test");
          }

          public long countTokens(UUID o, String m, String value) {
            return value.length() / 4 + 1;
          }

          public Reply generate(Request request, Consumer<String> text, BooleanSupplier cancel) {
            return new Reply(
                "Цель и ограничения сохранены. Незавершённое: продолжить текущую задачу.",
                List.of(),
                20L,
                10L);
          }
        };
    var memory = new MemoryService(store, records);
    var fact =
        store.transact(
            tx ->
                memory.save(
                    tx,
                    actor,
                    null,
                    null,
                    null,
                    new MemoryData("user", null, "source data stable preference", null, "active")));
    var builder =
        new ContextBuilder(
            store, provider, memory, records, new ContextCompactor(provider, json), json);
    var settings = new ProviderSettingsData("test", 8192, 1024, 100000);
    assertEquals(
        "cancelled",
        assertThrows(
                WorkspaceFailure.class,
                () ->
                    builder.build(conversation, settings, "Required rules", List.of(), () -> true))
            .code());
    var context =
        builder.build(
            conversation, settings, "Обязательно сохранять пользовательские файлы", List.of());
    long actual =
        provider.countTokens(
            actor.accountId(),
            "test",
            json.write(Map.of("messages", context, "functions", List.of())));
    assertTrue(actual <= (8192 - 1024 - 4096) * 0.6, Long.toString(actual));
    assertTrue(
        context.getFirst().content().contains("Обязательно сохранять пользовательские файлы"));
    assertTrue(context.getLast().content().contains("message-39"));
    assertEquals(
        40, store.transact(tx -> tx.history(actor.accountId(), conversation.id(), -1, 100)).size());
    assertTrue(
        store.transact(tx -> tx.latestSummary(actor.accountId(), conversation.id())).isPresent());
    store.transact(
        tx -> {
          for (int n = 0; n < 40; n++)
            chatAppend(conversations, tx, actor, conversation, "unrelated content ".repeat(40));
          return null;
        });
    builder.build(conversation, settings, "Required rules", List.of());
    var finalSummary =
        store.transact(tx -> tx.latestSummary(actor.accountId(), conversation.id())).orElseThrow();
    assertTrue(
        finalSummary.data().memoryIds().contains(fact.id()),
        "Memory provenance must survive repeated compaction");
    store.transact(
        tx -> {
          memory.delete(tx, actor, fact.id(), fact.version());
          return null;
        });
    assertTrue(
        store.transact(tx -> tx.latestSummary(actor.accountId(), conversation.id())).isEmpty());
  }

  @Test
  void frozenSessionDoesNotChangeWhenProfileIsEdited() {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("data.db"), json, clock);
    var records = new Records(clock);
    var actor = account(store, records);
    var settings = new ProviderSettingsService(store, records);
    var tools = new ToolDefinitions();
    var profiles = new ProfileService(store, records, new RoleCatalog(), tools);
    var options = new ProviderSettingsData("initial", 32768, 4096, 100000);
    store.transact(tx -> settings.save(tx, actor, options, null));
    var profile =
        store.transact(
            tx ->
                profiles.save(
                    tx,
                    actor,
                    null,
                    null,
                    null,
                    new ProfileData(
                        "BACKEND", "Пиши понятно", options, List.of("project_read_file"), 12)));
    var frozen =
        store.transact(tx -> profiles.freeze(tx, actor.accountId(), null, "BACKEND", null));
    store.transact(
        tx ->
            profiles.save(
                tx,
                actor,
                null,
                profile.id(),
                profile.version(),
                new ProfileData(
                    "BACKEND",
                    "Другая инструкция",
                    new ProviderSettingsData("new", 65536, 4096, 100000),
                    List.of("project_read_file", "process_run"),
                    24)));
    assertEquals("initial", frozen.settings().model());
    assertEquals(12, frozen.maxTurns());
    assertFalse(frozen.tools().contains("process_run"));
  }

  @Test
  void keepsToolExchangeTogetherWhenUserAnswersBeforeToolResult() {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("data.db"), json, clock);
    var records = new Records(clock);
    var actor = account(store, records);
    var chat = new ConversationService(records);
    var conversation = store.transact(tx -> chat.create(tx, actor, null, "Question"));
    store.transact(
        tx -> {
          chat.append(
              tx, actor.accountId(), null, conversation.id(), "user", "Goal", null, null, null);
          chat.append(
              tx,
              actor.accountId(),
              null,
              conversation.id(),
              "assistant",
              "Acknowledged",
              null,
              null,
              null);
          records.create(
              tx,
              EntityKind.MESSAGE,
              actor.accountId(),
              null,
              conversation.id(),
              new MessageData(
                  "assistant",
                  "",
                  2,
                  null,
                  null,
                  "state",
                  Map.of("name", "user_ask", "arguments", Map.of("question", "Which?"))));
          chat.append(
              tx,
              actor.accountId(),
              null,
              conversation.id(),
              "user",
              "First option",
              null,
              null,
              null);
          chat.append(
              tx,
              actor.accountId(),
              null,
              conversation.id(),
              "function",
              "{\"open\":true}",
              null,
              "user_ask",
              "state");
          return null;
        });
    var provider =
        new ProviderGateway() {
          public List<String> models(UUID owner) {
            return List.of("test");
          }

          public long countTokens(UUID owner, String model, String text) {
            return text.length() / 4 + 1;
          }

          public Reply generate(Request request, Consumer<String> text, BooleanSupplier cancelled) {
            return new Reply("Summary", List.of(), 1L, 1L);
          }
        };
    var compactor = new ContextCompactor(provider, json);
    var settings = new ProviderSettingsData("test", 32768, 4096, 100000);
    var source = store.transact(tx -> tx.history(actor.accountId(), conversation.id(), -1, 100));
    assertEquals(2, compactor.compact(conversation, settings, "", source, 4).consumed());
    var context =
        new ContextBuilder(
                store, provider, new MemoryService(store, records), records, compactor, json)
            .build(conversation, settings, "Instructions", List.of());
    assertEquals("assistant", context.get(3).role());
    assertEquals("function", context.get(4).role());
    assertEquals("First option", context.get(5).content());
    assertEquals("user", source.get(3).data().role(), "Original order must remain unchanged");
  }

  private void chatAppend(
      ConversationService chat,
      WorkspaceStore.Transaction tx,
      Actor actor,
      Entity<ConversationData> conversation,
      String content) {
    chat.append(tx, actor.accountId(), null, conversation.id(), "user", content, null, null, null);
  }

  private Actor account(WorkspaceStore store, Records records) {
    UUID id = UUID.randomUUID();
    store.transact(
        tx -> {
          tx.insert(
              EntityKind.ACCOUNT,
              new Entity<>(
                  id,
                  id,
                  null,
                  null,
                  0,
                  Instant.now(),
                  Instant.now(),
                  new AccountData("test@example.com", "hash", true, "Owner")));
          return null;
        });
    return new Actor(id, null, null, true);
  }
}
