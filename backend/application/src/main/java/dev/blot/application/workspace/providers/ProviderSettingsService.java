package dev.blot.application.workspace.providers;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentConfigurationData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import java.util.*;

public final class ProviderSettingsService {
  private final WorkspaceStore store;
  private final Records records;
  private final ProviderSettingsData defaults;

  public ProviderSettingsService(WorkspaceStore store, Records records) {
    this(store, records, null);
  }

  public ProviderSettingsService(
      WorkspaceStore store, Records records, ProviderSettingsData defaults) {
    this.store = store;
    this.records = records;
    this.defaults = defaults;
    if (defaults != null) validate(defaults);
  }

  public ProviderSettingsData get(UUID owner) {
    return store.transact(tx -> get(tx, owner));
  }

  public boolean managed() {
    return defaults != null;
  }

  public ProviderSettingsData get(WorkspaceStore.Transaction tx, UUID owner) {
    if (defaults != null) return defaults;
    return tx
        .list(EntityKind.PROVIDER_SETTINGS, owner, null, null, ProviderSettingsData.class, 1)
        .stream()
        .findFirst()
        .orElseThrow(
            () ->
                new WorkspaceFailure(
                    503,
                    "provider_unconfigured",
                    "Выберите модель и её проверенный лимит контекста"))
        .data();
  }

  public Entity<ProviderSettingsData> save(
      WorkspaceStore.Transaction tx, Actor actor, ProviderSettingsData value, Long version) {
    if (defaults != null)
      throw new WorkspaceFailure(
          403, "configuration_managed", "Модель и лимиты задаёт владелец установки через .env");
    validate(value);
    var old =
        tx.list(
            EntityKind.PROVIDER_SETTINGS,
            actor.accountId(),
            null,
            null,
            ProviderSettingsData.class,
            1);
    if (old.isEmpty())
      return records.create(tx, EntityKind.PROVIDER_SETTINGS, actor.accountId(), null, null, value);
    Records.version(old.getFirst(), version);
    return records.change(tx, EntityKind.PROVIDER_SETTINGS, old.getFirst(), value);
  }

  public static void validate(ProviderSettingsData value) {
    if (value == null) throw WorkspaceFailure.invalid("Нужны настройки модели");
    Records.text(value.model(), "model", 100);
    if (value.contextTokens() < 8192
        || value.contextTokens() > 2_000_000
        || value.outputTokens() < 256
        || value.outputTokens() > value.contextTokens() / 4
        || value.runTokenBudget() < value.contextTokens())
      throw WorkspaceFailure.invalid("Неверные лимиты модели");
  }

  public ProviderSettingsData forSession(UUID owner, UUID session) {
    if (session == null) return get(owner);
    return store.transact(
        tx ->
            tx
                .list(
                    EntityKind.AGENT_CONFIGURATION,
                    owner,
                    null,
                    session,
                    AgentConfigurationData.class,
                    1)
                .stream()
                .findFirst()
                .orElseThrow(
                    () ->
                        new WorkspaceFailure(
                            409,
                            "session_configuration_missing",
                            "Повторите задачу новым назначением"))
                .data()
                .settings());
  }
}
