package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.execution.SerializedProvider;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.execution.ModelRequestData;
import dev.blot.core.workspace.identity.AccountData;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ModelQueueTest {
  @TempDir Path directory;

  @Test
  void persistsWaitingAndActiveRequestsAndRecoversInterruptedQueue() throws Exception {
    var clock = Clock.systemUTC();
    var records = new Records(clock);
    var store = new SqliteWorkspaceStore(directory.resolve("state.db"), new JacksonCodec(), clock);
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
                  new AccountData("owner@example.com", "hash", true, "Owner")));
          return null;
        });
    var entered = new CountDownLatch(1);
    var finish = new CountDownLatch(1);
    var actual = new java.util.concurrent.atomic.AtomicInteger();
    var maximum = new java.util.concurrent.atomic.AtomicInteger();
    ProviderGateway provider =
        new ProviderGateway() {
          public String concurrencyKey(UUID owner) {
            return "shared-personal-access";
          }

          public List<String> models(UUID owner) {
            return List.of("test");
          }

          public long countTokens(UUID owner, String model, String text) {
            return 1;
          }

          public Reply generate(
              Request request, Consumer<String> output, BooleanSupplier cancelled) {
            maximum.accumulateAndGet(actual.incrementAndGet(), Math::max);
            entered.countDown();
            try {
              if (!finish.await(5, TimeUnit.SECONDS))
                throw new AssertionError("Test did not release model");
            } catch (InterruptedException failure) {
              Thread.currentThread().interrupt();
              throw new RuntimeException(failure);
            } finally {
              actual.decrementAndGet();
            }
            return new Reply("Done", List.of(), 10L, 5L);
          }
        };
    var queue = new SerializedProvider(provider, store, records);
    var request = new ProviderGateway.Request(owner, "test", List.of(), List.of(), 100);
    try (var workers = Executors.newVirtualThreadPerTaskExecutor()) {
      var first = workers.submit(() -> queue.generate(request, part -> {}, () -> false));
      assertTrue(entered.await(5, TimeUnit.SECONDS));
      UUID otherOwner = UUID.randomUUID();
      store.transact(
          tx -> {
            tx.insert(
                EntityKind.ACCOUNT,
                new Entity<>(
                    otherOwner,
                    otherOwner,
                    null,
                    null,
                    0,
                    clock.instant(),
                    clock.instant(),
                    new AccountData("second@example.com", "hash", true, "Second")));
            return null;
          });
      var otherRequest = new ProviderGateway.Request(otherOwner, "test", List.of(), List.of(), 100);
      var second = workers.submit(() -> queue.generate(otherRequest, part -> {}, () -> false));
      boolean waiting = false;
      for (int n = 0; n < 50; n++) {
        waiting =
            store
                .transact(
                    tx ->
                        tx.all(
                            EntityKind.MODEL_REQUEST,
                            otherOwner,
                            null,
                            null,
                            ModelRequestData.class))
                .stream()
                .anyMatch(row -> row.data().status().equals("QUEUED"));
        if (waiting) break;
        Thread.sleep(20);
      }
      assertTrue(waiting);
      finish.countDown();
      first.get(5, TimeUnit.SECONDS);
      second.get(5, TimeUnit.SECONDS);
      assertEquals(1, maximum.get());
    }
    assertTrue(
        store
            .transact(
                tx -> tx.all(EntityKind.MODEL_REQUEST, owner, null, null, ModelRequestData.class))
            .stream()
            .allMatch(
                row -> row.data().status().equals("COMPLETED") && row.data().inputTokens() == 10));
    var orphan =
        store.transact(
            tx ->
                records.create(
                    tx,
                    EntityKind.MODEL_REQUEST,
                    owner,
                    null,
                    null,
                    new ModelRequestData(
                        "test", "WORK", 0, "QUEUED", null, null, null, null, null)));
    queue.recover();
    assertEquals(
        "INTERRUPTED",
        store
            .transact(
                tx ->
                    Records.require(
                        tx, EntityKind.MODEL_REQUEST, owner, orphan.id(), ModelRequestData.class))
            .data()
            .status());
  }
}
