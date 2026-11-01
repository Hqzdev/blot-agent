package dev.blot.application.workspace.execution;

import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.workspace.WorkspaceFailure;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.*;

/** Повторяем только явный временный отказ до начала ответа, максимум три попытки. */
public final class RetryingProvider implements ProviderGateway {
  private final ProviderGateway provider;

  public RetryingProvider(ProviderGateway provider) {
    this.provider = provider;
  }

  public Reply generate(Request request, Consumer<String> output, BooleanSupplier cancelled) {
    var streamed = new AtomicBoolean();
    return retry(
        () ->
            provider.generate(
                request,
                part -> {
                  streamed.set(true);
                  output.accept(part);
                },
                cancelled),
        () -> !streamed.get(),
        cancelled);
  }

  public String concurrencyKey(UUID owner) {
    return provider.concurrencyKey(owner);
  }

  public List<String> models(UUID owner) {
    return retry(
        () -> provider.models(owner), () -> true, () -> Thread.currentThread().isInterrupted());
  }

  public long countTokens(UUID owner, String model, String text) {
    return retry(
        () -> provider.countTokens(owner, model, text),
        () -> true,
        () -> Thread.currentThread().isInterrupted());
  }

  private <T> T retry(Supplier<T> call, BooleanSupplier mayRetry, BooleanSupplier cancelled) {
    for (int attempt = 0; attempt < 3; attempt++) {
      if (cancelled.getAsBoolean()) throw new WorkspaceFailure(409, "cancelled", "Запрос отменён");
      try {
        return call.get();
      } catch (WorkspaceFailure failure) {
        if (attempt == 2
            || !mayRetry.getAsBoolean()
            || !Set.of("provider_temporary", "provider_rate_limit").contains(failure.code()))
          throw failure;
        int delay = attempt == 0 ? 5 : 15;
        for (int tick = 0; tick < delay; tick++) {
          if (cancelled.getAsBoolean())
            throw new WorkspaceFailure(409, "cancelled", "Ожидание повтора отменено");
          try {
            Thread.sleep(100);
          } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new WorkspaceFailure(409, "cancelled", "Ожидание повтора отменено");
          }
        }
      }
    }
    throw new IllegalStateException("Unreachable retry state");
  }
}
