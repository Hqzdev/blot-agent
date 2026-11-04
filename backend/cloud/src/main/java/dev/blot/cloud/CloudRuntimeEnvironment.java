package dev.blot.cloud;

import dev.blot.infrastructure.workspace.configuration.DotenvFile;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/** The same dotenv input as Apple builds. Process variables explicitly override file values. */
public final class CloudRuntimeEnvironment {
  private CloudRuntimeEnvironment() {}

  public static Map<String, String> load(Map<String, String> process) {
    var values = new HashMap<String, String>();
    String source = process.getOrDefault("BLOT_ENV_FILE", ".env");
    Path path = Path.of(source);
    if (process.containsKey("BLOT_ENV_FILE") || java.nio.file.Files.isRegularFile(path)) {
      new DotenvFile().read(path).forEach((key, value) -> values.put(key, value.toString()));
    }
    values.putAll(process);
    if (!values.containsKey("BLOT_GIGACHAT_CREDENTIALS")) {
      String key = values.get("BLOT_GIGACHAT_AUTH_KEY");
      if (key != null && !key.isBlank()) values.put("BLOT_GIGACHAT_CREDENTIALS", key);
    }
    return Map.copyOf(values);
  }
}
