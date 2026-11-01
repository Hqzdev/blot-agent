package dev.blot.application.workspace.conversation;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import java.util.*;

public final class ConversationService {
  private final Records records;

  public ConversationService(Records records) {
    this.records = records;
  }

  public Entity<ConversationData> create(
      WorkspaceStore.Transaction tx, Actor actor, UUID project, String title) {
    if (project != null)
      Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    return records.create(
        tx,
        EntityKind.CONVERSATION,
        actor.accountId(),
        project,
        null,
        new ConversationData(Records.text(title, "title", 200), "WORK", null, false));
  }

  public Entity<GenerationData> sendMessage(
      WorkspaceStore.Transaction tx, Actor actor, UUID conversationId, String text) {
    var conversation =
        Records.require(
            tx, EntityKind.CONVERSATION, actor.accountId(), conversationId, ConversationData.class);
    if (!conversation.data().mode().equals("WORK"))
      throw WorkspaceFailure.invalid("Внутренний чат агента управляется запуском");
    if (conversation.data().archived()) throw WorkspaceFailure.invalid("Чат в архиве");
    if (tx
        .list(
            EntityKind.GENERATION,
            actor.accountId(),
            null,
            conversationId,
            GenerationData.class,
            10000)
        .stream()
        .anyMatch(e -> Set.of("QUEUED", "RUNNING").contains(e.data().status())))
      throw new WorkspaceFailure(
          409, "generation_active", "Дождитесь ответа или отмените генерацию");
    var job =
        records.create(
            tx,
            EntityKind.GENERATION,
            actor.accountId(),
            conversation.projectId(),
            conversationId,
            new GenerationData(conversationId, null, "QUEUED", null, null, null));
    var message =
        append(
            tx,
            actor.accountId(),
            conversation.projectId(),
            conversationId,
            "user",
            Records.text(text, "content", 1_000_000),
            job.id(),
            null,
            null);
    String value = text.strip();
    if (value.toLowerCase(java.util.Locale.ROOT).startsWith("запомни:")) {
      String fact = Records.text(value.substring(8).strip(), "memory", 16000);
      records.create(
          tx,
          EntityKind.MEMORY,
          actor.accountId(),
          null,
          null,
          new MemoryData("user", null, fact, message.id(), "active"));
    } else {
      // Явная формулировка предпочтения создаёт только кандидата; факт подтверждает владелец.
      for (String line : value.lines().toList()) {
        String candidate = line.strip();
        String lower = candidate.toLowerCase(java.util.Locale.ROOT);
        if (candidate.length() <= 2000
            && (lower.startsWith("я предпочитаю ")
                || lower.startsWith("в проекте используем ")
                || lower.startsWith("i prefer ")
                || lower.startsWith("we use "))) {
          records.create(
              tx,
              EntityKind.MEMORY,
              actor.accountId(),
              conversation.projectId(),
              null,
              new MemoryData(
                  conversation.projectId() == null ? "user" : "project",
                  null,
                  candidate,
                  message.id(),
                  "candidate"));
          break;
        }
      }
    }
    return job;
  }

  public Entity<MessageData> append(
      WorkspaceStore.Transaction tx,
      UUID owner,
      UUID project,
      UUID conversation,
      String role,
      String content,
      UUID generation,
      String name,
      String state) {
    long ordinal = tx.nextOrdinal(owner, conversation);
    return records.create(
        tx,
        EntityKind.MESSAGE,
        owner,
        project,
        conversation,
        new MessageData(role, content, ordinal, generation, name, state));
  }

  public Entity<GenerationData> cancel(
      WorkspaceStore.Transaction tx, Actor actor, UUID generation) {
    var e =
        Records.require(
            tx, EntityKind.GENERATION, actor.accountId(), generation, GenerationData.class);
    if (!Set.of("QUEUED", "RUNNING").contains(e.data().status())) return e;
    var d = e.data();
    if (d.sessionId() != null) {
      var session =
          Records.require(
              tx,
              EntityKind.AGENT_SESSION,
              actor.accountId(),
              d.sessionId(),
              AgentSessionData.class);
      var state = session.data();
      records.change(
          tx,
          EntityKind.AGENT_SESSION,
          session,
          new AgentSessionData(
              state.role(),
              state.instruction(),
              state.taskId(),
              state.conversationId(),
              state.parentSessionId(),
              state.depth(),
              state.workspace(),
              "CANCELLED",
              "cancelled",
              state.turns()));
    }
    return records.change(
        tx,
        EntityKind.GENERATION,
        e,
        new GenerationData(
            d.conversationId(),
            d.sessionId(),
            "CANCELLED",
            "cancelled",
            d.inputTokens(),
            d.outputTokens()));
  }
}
