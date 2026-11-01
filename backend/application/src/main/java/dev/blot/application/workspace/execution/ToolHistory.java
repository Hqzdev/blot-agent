package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.conversation.MessageData;
import dev.blot.core.workspace.execution.GenerationData;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Восстанавливает границу между сохранённым вызовом и результатом инструмента. */
public final class ToolHistory {
  private final WorkspaceStore store;
  private final ConversationService conversations;
  private final ToolService tools;
  private final JsonCodec json;

  public ToolHistory(
      WorkspaceStore store, ConversationService conversations, ToolService tools, JsonCodec json) {
    this.store = store;
    this.conversations = conversations;
    this.tools = tools;
    this.json = json;
  }

  public void invoke(
      Entity<GenerationData> job,
      Entity<AgentSessionData> session,
      ProviderGateway.ToolCall call,
      BooleanSupplier cancelled) {
    var saved =
        latestCall(job)
            .orElseThrow(() -> WorkspaceFailure.invalid("Нет сохранённого вызова инструмента"));
    execute(job, session, call, saved.id(), cancelled);
  }

  public void repair(
      Entity<GenerationData> job, Entity<AgentSessionData> session, BooleanSupplier cancelled) {
    var pending = latestCall(job);
    if (pending.isEmpty()) return;
    var entry = pending.get();
    boolean answered =
        store.transact(
            tx ->
                tx
                    .history(
                        job.ownerId(), job.data().conversationId(), entry.data().ordinal(), 100)
                    .stream()
                    .anyMatch(message -> message.data().role().equals("function")));
    if (answered) return;
    var data = (Map<?, ?>) entry.data().functionCall();
    var call =
        new ProviderGateway.ToolCall(
            (String) data.get("name"), data.get("arguments"), entry.data().functionStateId());
    // Проверяемые инструменты возвращают сохранённый исход; UNKNOWN запрещает повторение.
    execute(job, session, call, entry.id(), cancelled);
  }

  private Optional<Entity<MessageData>> latestCall(Entity<GenerationData> job) {
    return store.transact(tx -> tx.latestToolCall(job.ownerId(), job.data().conversationId()));
  }

  private void execute(
      Entity<GenerationData> job,
      Entity<AgentSessionData> session,
      ProviderGateway.ToolCall call,
      UUID invocationId,
      BooleanSupplier cancelled) {
    Object result;
    WorkspaceFailure waiting = null;
    try {
      result = tools.execute(session, call, cancelled, invocationId);
    } catch (WorkspaceFailure failure) {
      if (failure.code().equals("cancelled") || failure.code().equals("operation_unknown"))
        throw failure;
      result = Map.of("error", failure.code(), "message", failure.getMessage());
      if (Set.of("permission_required", "child_wait").contains(failure.code())) waiting = failure;
    }
    Object output = result;
    store.transact(
        tx ->
            conversations.append(
                tx,
                job.ownerId(),
                job.projectId(),
                job.data().conversationId(),
                "function",
                json.write(output),
                job.id(),
                call.name(),
                call.stateId()));
    if (waiting != null) throw waiting;
    if (call.name().equals("user_ask"))
      throw new WorkspaceFailure(403, "permission_required", "Ожидание ответа пользователя");
  }
}
