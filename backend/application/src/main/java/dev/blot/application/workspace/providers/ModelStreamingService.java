package dev.blot.application.workspace.providers;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.conversation.ConversationData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.execution.GenerationData;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Сохраняет частичный текст и полный вызов функции, полученные от провайдера. */
public final class ModelStreamingService {
  private final WorkspaceStore store;
  private final Records records;
  private final ProviderGateway provider;
  private final ConversationService conversations;

  public ModelStreamingService(
      WorkspaceStore store,
      Records records,
      ProviderGateway provider,
      ConversationService conversations) {
    this.store = store;
    this.records = records;
    this.provider = provider;
    this.conversations = conversations;
  }

  public ProviderGateway.Reply generate(
      Entity<GenerationData> job,
      ProviderSettingsData settings,
      List<ProviderGateway.Message> messages,
      List<ProviderGateway.Function> functions,
      BooleanSupplier cancelled) {
    var message =
        store.transact(
            tx ->
                conversations.append(
                    tx,
                    job.ownerId(),
                    job.projectId(),
                    job.data().conversationId(),
                    "assistant",
                    "",
                    job.id(),
                    null,
                    null));
    var partial = new StringBuilder();
    var last = new AtomicLong(System.nanoTime());
    var conversation =
        store.transact(
            tx ->
                Records.require(
                    tx,
                    EntityKind.CONVERSATION,
                    job.ownerId(),
                    job.data().conversationId(),
                    ConversationData.class));
    try {
      var reply =
          provider.generate(
              new ProviderGateway.Request(
                  job.ownerId(),
                  settings.model(),
                  messages,
                  functions,
                  settings.outputTokens(),
                  job.projectId(),
                  conversation.data().runId(),
                  job.data().sessionId()),
              part -> {
                partial.append(part);
                if (System.nanoTime() - last.get() > 250_000_000L) {
                  saveText(job, message.id(), partial.toString());
                  last.set(System.nanoTime());
                }
              },
              cancelled);
      if (partial.isEmpty() && !reply.text().isEmpty()) partial.append(reply.text());
      if (reply.calls().size() > 1)
        throw WorkspaceFailure.invalid("Ожидался один полный вызов функции");
      if (reply.calls().stream()
          .anyMatch(call -> functions.stream().noneMatch(f -> f.name().equals(call.name()))))
        throw WorkspaceFailure.invalid("Провайдер вернул недоступную функцию");
      if (!reply.calls().isEmpty()) {
        var call = reply.calls().getFirst();
        store.transact(
            tx -> {
              var m =
                  Records.require(
                      tx, EntityKind.MESSAGE, job.ownerId(), message.id(), MessageData.class);
              var d = m.data();
              records.change(
                  tx,
                  EntityKind.MESSAGE,
                  m,
                  new MessageData(
                      d.role(),
                      reply.text(),
                      d.ordinal(),
                      d.generationId(),
                      null,
                      call.stateId(),
                      Map.of("name", call.name(), "arguments", call.arguments())));
              return null;
            });
      }
      return reply;
    } finally {
      saveText(job, message.id(), partial.toString());
    }
  }

  private void saveText(Entity<GenerationData> job, UUID id, String text) {
    store.transact(
        tx -> {
          var m = Records.require(tx, EntityKind.MESSAGE, job.ownerId(), id, MessageData.class);
          var d = m.data();
          records.change(
              tx,
              EntityKind.MESSAGE,
              m,
              new MessageData(
                  d.role(),
                  text,
                  d.ordinal(),
                  d.generationId(),
                  d.functionName(),
                  d.functionStateId(),
                  d.functionCall()));
          return null;
        });
  }
}
