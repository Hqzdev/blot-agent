package dev.blot.cloud.model;

import dev.blot.application.ports.ProviderGateway;
import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.Semaphore;
import java.util.function.*;

public final class CloudModelGateway {
  public record Message(String role, String content) {}

  public record Completion(UUID requestID, String model, List<Message> messages, int max_tokens) {
    public Completion {
      if (messages != null) {
        if (messages.stream().anyMatch(Objects::isNull))
          throw new CloudFailure(400, "invalid_generation");
        messages = List.copyOf(messages);
      }
    }
  }

  public record Prepared(CloudActor actor, Completion request) {}

  private final ProviderGateway provider;
  private final CloudModelQuota quota;
  // The built-in credential has one provider concurrency budget across all accounts.
  private final Semaphore slot = new Semaphore(1);

  public CloudModelGateway(ProviderGateway provider, CloudModelQuota quota) {
    this.provider = provider;
    this.quota = quota;
  }

  public Prepared prepare(CloudActor actor, Completion request) {
    if (request == null
        || request.requestID() == null
        || request.model() == null
        || !request.model().matches("GigaChat[A-Za-z0-9._-]{0,60}")
        || request.messages() == null
        || request.messages().isEmpty()
        || request.messages().size() > 200
        || request.max_tokens() < 1
        || request.max_tokens() > 8192) throw new CloudFailure(400, "invalid_generation");
    long input = 0;
    for (Message message : request.messages()) {
      if (message == null
          || message.role() == null
          || !Set.of("system", "user", "assistant").contains(message.role())
          || message.content() == null) throw new CloudFailure(400, "invalid_generation");
      input += message.content().getBytes(StandardCharsets.UTF_8).length + 32;
    }
    if (input > 131_072) throw new CloudFailure(413, "context_too_large");
    // The built-in adapter requires configured credentials to resolve its concurrency key.
    provider.concurrencyKey(actor.ownerID());
    quota.reserve(actor, request.requestID(), input + request.max_tokens());
    return new Prepared(actor, request);
  }

  public ProviderGateway.Reply generate(
      Prepared prepared, Consumer<String> text, BooleanSupplier canceled) {
    boolean acquired = false, invoked = false, claimed = false, settled = false;
    try {
      while (!(acquired = slot.tryAcquire(1, java.util.concurrent.TimeUnit.SECONDS))) {
        if (canceled.getAsBoolean()) throw new CloudFailure(409, "generation_canceled");
      }
      quota.start(prepared.actor(), prepared.request().requestID());
      claimed = true;
      if (canceled.getAsBoolean()) throw new CloudFailure(409, "generation_canceled");
      Completion request = prepared.request();
      var messages =
          request.messages().stream()
              .map(m -> new ProviderGateway.Message(m.role(), m.content(), null, null))
              .toList();
      invoked = true;
      var reply =
          provider.generate(
              new ProviderGateway.Request(
                  prepared.actor().ownerID(),
                  request.model(),
                  messages,
                  List.of(),
                  request.max_tokens()),
              text,
              canceled);
      Long actual =
          reply.inputTokens() == null || reply.outputTokens() == null
              ? null
              : Math.addExact(reply.inputTokens(), reply.outputTokens());
      quota.settle(prepared.actor(), request.requestID(), actual);
      settled = true;
      if (!reply.calls().isEmpty()) throw new CloudFailure(502, "unexpected_tool_call");
      return reply;
    } catch (InterruptedException failure) {
      Thread.currentThread().interrupt();
      if (claimed)
        quota.settle(prepared.actor(), prepared.request().requestID(), invoked ? null : 0L);
      else quota.abandonReserved(prepared.actor(), prepared.request().requestID());
      throw new CloudFailure(409, "generation_canceled");
    } catch (RuntimeException failure) {
      if (claimed && !settled)
        quota.settle(prepared.actor(), prepared.request().requestID(), invoked ? null : 0L);
      else if (!claimed) quota.abandonReserved(prepared.actor(), prepared.request().requestID());
      throw failure;
    } finally {
      if (acquired) slot.release();
    }
  }
}
