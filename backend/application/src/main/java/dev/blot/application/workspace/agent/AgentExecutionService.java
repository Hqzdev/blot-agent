package dev.blot.application.workspace.agent;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.ContextBuilder;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.execution.ToolHistory;
import dev.blot.application.workspace.execution.ToolService;
import dev.blot.application.workspace.profile.ProfileService;
import dev.blot.application.workspace.providers.ModelStreamingService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.InboxData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Последовательный цикл одной сессии: модель, проверенный инструмент, результат. */
public final class AgentExecutionService {
  private final WorkspaceStore store;
  private final Records records;
  private final ConversationService conversations;
  private final ContextBuilder context;
  private final ModelStreamingService streaming;
  private final ToolService tools;
  private final AgentResultService results;
  private final ProfileService profiles;
  private final ToolHistory toolHistory;

  public AgentExecutionService(
      WorkspaceStore store,
      Records records,
      ConversationService conversations,
      ContextBuilder context,
      ModelStreamingService streaming,
      ToolService tools,
      AgentResultService results,
      ProfileService profiles,
      ToolHistory toolHistory) {
    this.store = store;
    this.records = records;
    this.conversations = conversations;
    this.context = context;
    this.streaming = streaming;
    this.tools = tools;
    this.results = results;
    this.profiles = profiles;
    this.toolHistory = toolHistory;
  }

  public ProviderGateway.Reply execute(
      Entity<GenerationData> job,
      Entity<ConversationData> conversation,
      ProviderSettingsData settings,
      BooleanSupplier cancelled) {
    var session =
        store.transact(
            tx ->
                Records.require(
                    tx,
                    EntityKind.AGENT_SESSION,
                    job.ownerId(),
                    job.data().sessionId(),
                    AgentSessionData.class));
    toolHistory.repair(job, session, cancelled);
    var configuration = profiles.config(job.ownerId(), session.id());
    for (int turn = session.data().turns(); turn < configuration.maxTurns(); turn++) {
      if (cancelled.getAsBoolean())
        throw new WorkspaceFailure(409, "cancelled", "Работа остановлена");
      var fresh =
          store.transact(
              tx ->
                  Records.require(
                      tx,
                      EntityKind.AGENT_SESSION,
                      job.ownerId(),
                      session.id(),
                      AgentSessionData.class));
      var d = fresh.data();
      int nextTurn = turn + 1;
      store.transact(
          tx -> {
            records.change(
                tx,
                EntityKind.AGENT_SESSION,
                fresh,
                new AgentSessionData(
                    d.role(),
                    d.instruction(),
                    d.taskId(),
                    d.conversationId(),
                    d.parentSessionId(),
                    d.depth(),
                    d.workspace(),
                    "RUNNING",
                    null,
                    nextTurn));
            for (var inbox :
                tx.list(
                    EntityKind.INBOX,
                    job.ownerId(),
                    job.projectId(),
                    session.id(),
                    InboxData.class,
                    100)) {
              if (!inbox.data().processed()) {
                conversations.append(
                    tx,
                    job.ownerId(),
                    job.projectId(),
                    conversation.id(),
                    "user",
                    "Сообщение коллеги "
                        + inbox.data().senderSessionId()
                        + ": "
                        + inbox.data().content(),
                    job.id(),
                    null,
                    null);
                var i = inbox.data();
                records.change(tx, EntityKind.INBOX, inbox, i.markProcessed());
              }
            }
            return null;
          });
      var functions =
          tools.functions(d.role()).stream()
              .filter(f -> configuration.tools().contains(f.name()))
              .toList();
      var messages = context.build(conversation, settings, d.instruction(), functions, cancelled);
      var reply = streaming.generate(job, settings, messages, functions, cancelled);
      if (reply.calls().isEmpty()) {
        results.complete(job, fresh, reply);
        return reply;
      }
      for (var call : reply.calls()) {
        if (functions.stream().noneMatch(f -> f.name().equals(call.name())))
          throw WorkspaceFailure.invalid("Модель запросила недоступный инструмент");
        toolHistory.invoke(job, session, call, cancelled);
      }
    }
    throw new WorkspaceFailure(429, "turn_limit", "Достигнут лимит шагов сессии");
  }
}
