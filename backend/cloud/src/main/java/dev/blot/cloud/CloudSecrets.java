package dev.blot.cloud;

import dev.blot.application.ports.SecretStore;
import java.nio.file.*;
import java.util.*;

/** Deployment-controlled secrets; neither a client endpoint nor a replicated store. */
public final class CloudSecrets implements SecretStore {
  private final Map<String, String> environment;

  public CloudSecrets(Map<String, String> environment) {
    this.environment = Map.copyOf(environment);
  }

  public Optional<String> get(String key) {
    String name =
        key.startsWith("provider.ca.")
            ? "BLOT_GIGACHAT_CA"
            : key.startsWith("provider.")
                ? "BLOT_GIGACHAT_CREDENTIALS"
                : "BLOT_" + key.toUpperCase(Locale.ROOT).replace('.', '_');
    String file = environment.get(name + "_FILE");
    if (file != null) {
      try {
        Path path = Path.of(file);
        if (Files.size(path) > 131_072) throw new CloudFailure(503, "secret_unavailable");
        return Optional.of(Files.readString(path).strip()).filter(v -> !v.isEmpty());
      } catch (java.io.IOException failure) {
        throw new CloudFailure(503, "secret_unavailable");
      }
    }
    return Optional.ofNullable(environment.get(name)).filter(v -> !v.isBlank());
  }

  public void put(String key, String value) {
    throw new UnsupportedOperationException("Cloud secrets are deployment-controlled");
  }

  public void remove(String key) {
    throw new UnsupportedOperationException("Cloud secrets are deployment-controlled");
  }
}
