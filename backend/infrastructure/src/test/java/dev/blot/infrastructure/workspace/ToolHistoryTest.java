package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProcessGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.agent.AgentCommunicationTools;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.agent.DelegationService;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.execution.PreparedActionExecutor;
import dev.blot.application.workspace.execution.ToolHistory;
import dev.blot.application.workspace.execution.ToolService;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.InboxData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.infrastructure.workspace.artifacts.LocalArtifactStore;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import dev.blot.infrastructure.workspace.git.LocalGitGateway;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ToolHistoryTest {
  @TempDir Path directory;

  @Test
  void repairsSavedToolResultAndDoesNotResendMessage() {
    var clock = Clock.systemUTC();
    var json = new JacksonCodec();
    var store = new SqliteWorkspaceStore(directory.resolve("state.db"), json, clock);
    var records = new Records(clock);
    UUID owner = UUID.randomUUID();
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
                  new AccountData("test@example.com", "hash", true, "Owner")));
          return null;
        });
    var chat = new ConversationService(records);
    var conversation =
        store.transact(tx -> chat.create(tx, new Actor(owner, null, null, true), null, "Recovery"));
    UUID run = UUID.randomUUID();
    var session =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.AGENT_SESSION,
                    owner,
                    null,
                    run,
                    new AgentSessionData(
                        "BACKEND",
                        "Instruction",
                        UUID.randomUUID(),
                        conversation.id(),
                        null,
                        0,
                        directory.toString(),
                        "RUNNING",
                        null,
                        1)));
    var recipient =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.AGENT_SESSION,
                    owner,
                    null,
                    run,
                    new AgentSessionData(
                        "BACKEND",
                        "Instruction",
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        null,
                        0,
                        directory.toString(),
                        "RUNNING",
                        null,
                        1)));
    var job =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.GENERATION,
                    owner,
                    null,
                    conversation.id(),
                    new GenerationData(
                        conversation.id(), session.id(), "RUNNING", null, null, null)));
    var tokens = new TokenGenerator();
    var permissions = new PermissionService(records, json, tokens, clock);
    var artifacts = new LocalArtifactStore(directory.resolve("artifacts"));
    var files = new AgentFiles(store, tokens, artifacts, records);
    var git = new LocalGitGateway(directory.resolve("workspaces"));
    ProcessGateway processes =
        (path, scopes, program, args, timeout, cancel) -> {
          throw new AssertionError("Completed operation must not run again");
        };
    var actions =
        new PreparedActionExecutor(
            store, records, permissions, git, processes, artifacts, tokens, files);
    var communication = new AgentCommunicationTools(store, records);
    var tools =
        new ToolService(
            store,
            permissions,
            git,
            json,
            tokens,
            new DelegationService(store, records),
            new ToolDefinitions(),
            files,
            actions,
            communication);
    var history = new ToolHistory(store, chat, tools, json);
    var action =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.PREPARED_ACTION,
                    owner,
                    null,
                    session.id(),
                    new PreparedActionData(
                        "patch.apply",
                        session.id(),
                        session.data().taskId(),
                        "base",
                        Map.of(),
                        "hash",
                        "FINISHED")));
    store.transact(
        tx ->
            records.create(
                tx,
                EntityKind.TOOL_OPERATION,
                owner,
                null,
                action.id(),
                new ToolOperationData(
                    session.id(),
                    action.id(),
                    "patch.apply",
                    "FINISHED",
                    Map.of("hash", "saved"),
                    null)));
    appendCall(
        store,
        records,
        conversation,
        job,
        "patch_apply",
        Map.of("preparedActionId", action.id().toString()));
    history.repair(job, session, () -> false);
    history.repair(job, session, () -> false);
    assertEquals(
        1,
        store.transact(tx -> tx.history(owner, conversation.id(), -1, 100)).stream()
            .filter(e -> e.data().role().equals("function"))
            .count());
    var args =
        Map.<String, Object>of(
            "recipientSessionId", recipient.id().toString(), "content", "Evidence");
    var call = appendCall(store, records, conversation, job, "task_message", args);
    communication.message(session, args, call.id());
    history.repair(job, session, () -> false);
    assertEquals(
        1,
        store
            .transact(tx -> tx.all(EntityKind.INBOX, owner, null, recipient.id(), InboxData.class))
            .size());
  }

  private Entity<MessageData> appendCall(
      WorkspaceStore store,
      Records records,
      Entity<ConversationData> conversation,
      Entity<GenerationData> job,
      String name,
      Map<String, Object> args) {
    return store.transact(
        tx ->
            records.create(
                tx,
                EntityKind.MESSAGE,
                job.ownerId(),
                null,
                conversation.id(),
                new MessageData(
                    "assistant",
                    "",
                    tx.nextOrdinal(job.ownerId(), conversation.id()),
                    job.id(),
                    null,
                    "state",
                    Map.of("name", name, "arguments", args))));
  }
}
