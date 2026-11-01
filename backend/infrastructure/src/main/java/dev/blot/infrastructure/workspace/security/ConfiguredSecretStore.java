package dev.blot.infrastructure.workspace.security;

import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.WorkspaceFailure;
import java.util.*;

/** Общие секреты установки имеют приоритет; пользователь не может заменить их через API. */
public final class ConfiguredSecretStore implements SecretStore {
  private final Map<String, String> values;
  private final SecretStore personal;

  public ConfiguredSecretStore(Map<String, String> values, SecretStore personal) {
    this.values = Map.copyOf(values);
    this.personal = personal;
  }

  public Optional<String> get(String key) {
    if (managed(key)) return Optional.ofNullable(values.get(configurationKey(key)));
    return personal.get(key);
  }

  public void put(String key, String value) {
    requirePersonal(key);
    personal.put(key, value);
  }

  public void remove(String key) {
    requirePersonal(key);
    personal.remove(key);
  }

  private boolean managed(String key) {
    return key.startsWith("smtp.") && values.containsKey("smtp.host")
        || key.startsWith("provider.") && values.containsKey("provider.key");
  }

  private String configurationKey(String key) {
    if (key.startsWith("provider.ca.")) return "provider.ca";
    if (key.startsWith("provider.")) return "provider.key";
    return key;
  }

  private void requirePersonal(String key) {
    if (managed(key))
      throw new WorkspaceFailure(
          403, "configuration_managed", "Эту настройку задаёт владелец установки через .env");
  }
}
