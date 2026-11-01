package dev.blot.application.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.execution.ModelRequestData;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;

/** Одна FIFO очередь генерации на доступ. Положение каждого запроса видно в базе. */
public final class SerializedProvider implements ProviderGateway {
  private final ProviderGateway provider;
  private final WorkspaceStore store;
  private final Records records;
  private final Map<String, Semaphore> queues = new ConcurrentHashMap<>();

  public SerializedProvider(ProviderGateway provider, WorkspaceStore store, Records records) {
    this.provider = provider;
    this.store = store;
    this.records = records;
  }

  public Reply generate(Request request, Consumer<String> output, BooleanSupplier cancelled) {
    var pending =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.MODEL_REQUEST,
                    request.ownerId(),
                    request.projectId(),
                    request.sessionId(),
                    new ModelRequestData(
                        request.model(),
                        request.purpose(),
                        0,
                        "QUEUED",
                        request.runId(),
                        request.sessionId(),
                        null,
                        null,
                        null)));
    Semaphore queue = null;
    boolean acquired = false;
    try {
      String credential = provider.concurrencyKey(request.ownerId());
      queue = queues.computeIfAbsent(credential, id -> new Semaphore(1, true));
      while (!(acquired = queue.tryAcquire(200, TimeUnit.MILLISECONDS)))
        if (cancelled.getAsBoolean()) throw stopped();
      if (cancelled.getAsBoolean()) throw stopped();
      change(pending, "RUNNING", null, null);
      var reply = provider.generate(request, output, cancelled);
      change(pending, "COMPLETED", reply, null);
      return reply;
    } catch (InterruptedException interrupted) {
      Thread.currentThread().interrupt();
      change(pending, "CANCELLED", null, "cancelled");
      throw stopped();
    } catch (WorkspaceFailure failure) {
      change(
          pending,
          failure.code().equals("cancelled") ? "CANCELLED" : "FAILED",
          null,
          failure.code());
      throw failure;
    } catch (RuntimeException failure) {
      change(pending, "FAILED", null, "internal");
      throw failure;
    } finally {
      if (acquired) queue.release();
    }
  }

  public void recover() {
    while (store.transact(
        tx -> {
          var interrupted =
              tx.states(
                  EntityKind.MODEL_REQUEST,
                  ModelRequestData.class,
                  List.of("QUEUED", "RUNNING"),
                  1000);
          for (var entry : interrupted) {
            var data = entry.data();
            records.change(
                tx,
                EntityKind.MODEL_REQUEST,
                entry,
                new ModelRequestData(
                    data.model(),
                    data.purpose(),
                    data.priority(),
                    "INTERRUPTED",
                    data.runId(),
                    data.sessionId(),
                    data.inputTokens(),
                    data.outputTokens(),
                    "host_restarted"));
          }
          return !interrupted.isEmpty();
        })) {}
  }

  private void change(Entity<ModelRequestData> request, String status, Reply reply, String error) {
    store.transact(
        tx -> {
          var current =
              Records.require(
                  tx,
                  EntityKind.MODEL_REQUEST,
                  request.ownerId(),
                  request.id(),
                  ModelRequestData.class);
          var data = current.data();
          records.change(
              tx,
              EntityKind.MODEL_REQUEST,
              current,
              new ModelRequestData(
                  data.model(),
                  data.purpose(),
                  data.priority(),
                  status,
                  data.runId(),
                  data.sessionId(),
                  reply == null ? null : reply.inputTokens(),
                  reply == null ? null : reply.outputTokens(),
                  error));
          return null;
        });
  }

  public String concurrencyKey(UUID owner) {
    return provider.concurrencyKey(owner);
  }

  public List<String> models(UUID owner) {
    return provider.models(owner);
  }

  public long countTokens(UUID owner, String model, String text) {
    return provider.countTokens(owner, model, text);
  }

  private WorkspaceFailure stopped() {
    return new WorkspaceFailure(409, "cancelled", "Ожидание модели отменено");
  }
}
