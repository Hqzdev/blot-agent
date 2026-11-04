package dev.blot.application.workspace.billing;

import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import java.util.*;
import java.util.function.*;

/** Каждый вызов, включая сжатие истории, учитывается в бюджете. */
public final class BudgetedProvider implements ProviderGateway {
  private final ProviderGateway provider;
  private final BudgetService budgets;
  private final ProviderSettingsService settings;
  private final dev.blot.application.ports.JsonCodec json;

  public BudgetedProvider(
      ProviderGateway provider,
      BudgetService budgets,
      ProviderSettingsService settings,
      dev.blot.application.ports.JsonCodec json) {
    this.provider = provider;
    this.budgets = budgets;
    this.settings = settings;
    this.json = json;
  }

  public Reply generate(Request request, Consumer<String> text, BooleanSupplier cancelled) {
    long reserve =
        countTokens(
                request.ownerId(),
                request.model(),
                json.write(
                    Map.of("messages", request.messages(), "functions", request.functions())))
            + request.maxOutputTokens()
            + 4096;
    var id =
        budgets.reserve(
            request,
            reserve,
            settings.forSession(request.ownerId(), request.sessionId()).runTokenBudget());
    Long actual = null;
    try {
      var reply = provider.generate(request, text, cancelled);
      if (reply.inputTokens() != null && reply.outputTokens() != null)
        actual = reply.inputTokens() + reply.outputTokens();
      return reply;
    } finally {
      budgets.settle(request.ownerId(), id, actual);
    }
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
}
