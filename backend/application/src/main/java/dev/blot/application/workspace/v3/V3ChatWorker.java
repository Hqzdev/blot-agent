package dev.blot.application.workspace.v3;

import dev.blot.application.ports.*;
import dev.blot.core.v3.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;

/** Persisted pending replies survive restart; an ambiguous provider call is never retried. */
public final class V3ChatWorker implements AutoCloseable {
  private final V3Store store;
  private final V3Workspace workspace;
  private final JsonCodec json;
  private final ProviderGateway provider;
  private final ScheduledExecutorService worker =
      Executors.newSingleThreadScheduledExecutor(
          Thread.ofPlatform().name("blot-v3-chat").factory());

  public V3ChatWorker(
      V3Store store, V3Workspace workspace, JsonCodec json, ProviderGateway provider) {
    this.store = store;
    this.workspace = workspace;
    this.json = json;
    this.provider = provider;
    for (var owner : store.owners()) {
      store.transact(
          owner,
          tx -> {
            for (var record : tx.records("Message")) {
              var message = json.convert(record.value(), Message.class);
              if (message.role() == MessageRole.ASSISTANT
                  && message.delivery() == DeliveryState.RUNNING)
                update(
                    tx,
                    owner,
                    message,
                    DeliveryState.INTERRUPTED,
                    "Ответ прерван при перезапуске сервера.");
            }
            return null;
          });
    }
    worker.scheduleWithFixedDelay(this::tick, 0, 300, TimeUnit.MILLISECONDS);
  }

  private record Pending(
      UUID owner, Message response, AgentProfile agent, List<ProviderGateway.Message> context) {}

  private void tick() {
    try {
      for (var owner : store.owners()) {
        if (Thread.currentThread().isInterrupted()) return;
        var pending = claim(owner);
        if (pending == null) continue;
        try {
          var result =
              provider.generate(
                  new ProviderGateway.Request(
                      owner, pending.agent().modelId(), pending.context(), List.of(), 4096),
                  ignored -> {},
                  () -> Thread.currentThread().isInterrupted());
          if (!result.calls().isEmpty())
            throw new IllegalStateException("Tool execution is not available in this runtime");
          finish(pending, DeliveryState.COMPLETED, result.text());
        } catch (RuntimeException failure) {
          finish(
              pending,
              DeliveryState.FAILED,
              "Не удалось получить ответ. Проверьте подключение и настройки модели.");
        }
      }
    } catch (RuntimeException failure) {
      System.getLogger(V3ChatWorker.class.getName())
          .log(System.Logger.Level.WARNING, "v3 chat worker could not process its queue");
    }
  }

  private Pending claim(UUID owner) {
    return store.transact(
        owner,
        tx -> {
          for (var record : tx.records("Message")) {
            var message = json.convert(record.value(), Message.class);
            if (message.role() != MessageRole.ASSISTANT
                || message.delivery() != DeliveryState.SAVED) continue;
            var chat =
                json.convert(
                    workspace.require(tx, "Conversation", message.conversationId()).value(),
                    Conversation.class);
            var agent =
                json.convert(
                    workspace.require(tx, "AgentProfile", chat.agentId()).value(),
                    AgentProfile.class);
            var context = new ArrayList<ProviderGateway.Message>();
            context.add(new ProviderGateway.Message("system", agent.instructions(), null, null));
            var history =
                tx.records("Message").stream()
                    .map(r -> json.convert(r.value(), Message.class))
                    .filter(
                        m ->
                            m.conversationId().equals(chat.metadata().id())
                                && !m.metadata().id().equals(message.metadata().id())
                                && (m.role() == MessageRole.USER
                                    || m.delivery() == DeliveryState.COMPLETED))
                    .sorted(Comparator.comparing(m -> Objects.requireNonNullElse(m.position(), 0L)))
                    .toList();
            int characters = 0;
            var recent = new ArrayList<ProviderGateway.Message>();
            for (int i = history.size() - 1; i >= 0; i--) {
              var m = history.get(i);
              if (characters + m.content().length() > 48_000) {
                if (recent.isEmpty()) {
                  update(
                      tx,
                      owner,
                      message,
                      DeliveryState.FAILED,
                      "Сообщение превышает допустимый размер контекста.");
                  return null;
                }
                break;
              }
              characters += m.content().length();
              recent.add(
                  new ProviderGateway.Message(
                      m.role() == MessageRole.USER ? "user" : "assistant",
                      m.content(),
                      null,
                      null));
            }
            Collections.reverse(recent);
            context.addAll(recent);
            update(tx, owner, message, DeliveryState.RUNNING, "");
            return new Pending(owner, message, agent, List.copyOf(context));
          }
          return null;
        });
  }

  private void finish(Pending pending, DeliveryState state, String content) {
    store.transact(
        pending.owner(),
        tx -> {
          tx.find("Message", pending.response().metadata().id())
              .filter(r -> !r.deleted())
              .ifPresent(
                  record -> {
                    var message = json.convert(record.value(), Message.class);
                    if (message.delivery() == DeliveryState.RUNNING)
                      update(tx, pending.owner(), message, state, content == null ? "" : content);
                  });
          return null;
        });
  }

  private void update(
      V3Store.Transaction tx, UUID owner, Message message, DeliveryState state, String content) {
    var old = workspace.require(tx, "Message", message.metadata().id());
    var metadata = workspace.metadata(owner, old.id(), old.version() + 1, old);
    workspace.put(
        tx,
        "Message",
        metadata,
        new Message(
            metadata,
            message.conversationId(),
            message.role(),
            content,
            state,
            message.commandId(),
            message.artifactIds(),
            message.authorAgentId(),
            message.replyToMessageId(),
            message.mentions(),
            message.position(),
            message.executorDeviceId()));
  }

  public void close() {
    worker.shutdownNow();
    try {
      worker.awaitTermination(Duration.ofSeconds(5).toMillis(), TimeUnit.MILLISECONDS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
}
