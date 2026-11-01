package dev.blot.application.workspace.conversation;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.conversation.SummaryData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.identity.Actor;
import java.util.*;

/** Изменения истории Work выполняются отдельно от удаления долговременной памяти. */
public final class ConversationLifecycle {
  private final Records records;
  private final MemoryService memory;

  public ConversationLifecycle(Records records, MemoryService memory) {
    this.records = records;
    this.memory = memory;
  }

  public Entity<ConversationData> change(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID id,
      Long version,
      String title,
      Boolean archived) {
    var conversation =
        Records.require(tx, EntityKind.CONVERSATION, actor.accountId(), id, ConversationData.class);
    Records.version(conversation, version);
    var data = conversation.data();
    if (!data.mode().equals("WORK"))
      throw WorkspaceFailure.invalid("Внутренний чат управляется запуском");
    return records.change(
        tx,
        EntityKind.CONVERSATION,
        conversation,
        new ConversationData(
            title == null ? data.title() : Records.text(title, "title", 200),
            data.mode(),
            data.runId(),
            archived == null ? data.archived() : archived,
            data.requirementsVersion()));
  }

  public void deleteMessage(WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var message = Records.require(tx, EntityKind.MESSAGE, actor.accountId(), id, MessageData.class);
    Records.version(message, version);
    var conversation =
        Records.require(
            tx,
            EntityKind.CONVERSATION,
            actor.accountId(),
            message.parentId(),
            ConversationData.class);
    if (!conversation.data().mode().equals("WORK"))
      throw WorkspaceFailure.invalid("История исполнителя сохраняется вместе с запуском");
    if (tx
        .all(
            EntityKind.GENERATION, actor.accountId(), null, conversation.id(), GenerationData.class)
        .stream()
        .anyMatch(job -> Set.of("QUEUED", "RUNNING").contains(job.data().status())))
      throw WorkspaceFailure.conflict("Сначала завершите или отмените генерацию");
    for (var summary :
        tx.all(EntityKind.SUMMARY, actor.accountId(), null, conversation.id(), SummaryData.class)) {
      var data = summary.data();
      if (data.valid() && data.throughOrdinal() >= message.data().ordinal())
        records.change(
            tx,
            EntityKind.SUMMARY,
            summary,
            new SummaryData(
                data.conversationId(),
                data.throughOrdinal(),
                data.content(),
                data.memoryIds(),
                false));
    }
    memory.removeSource(tx, actor, message.id());
    tx.delete(EntityKind.MESSAGE, actor.accountId(), id);
    tx.event(
        actor.accountId(),
        conversation.projectId(),
        "message.deleted",
        Map.of("id", id, "conversationId", conversation.id()));
  }
}
