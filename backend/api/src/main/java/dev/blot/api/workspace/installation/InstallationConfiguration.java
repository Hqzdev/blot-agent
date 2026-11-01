package dev.blot.api.workspace.installation;

import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import dev.blot.infrastructure.workspace.provider.PemCertificates;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import org.springframework.core.env.Environment;

/** Параметры владельца проверяются один раз, до обработки пользовательских запросов. */
public final class InstallationConfiguration {
  private final Map<String, String> secrets;
  private final ProviderSettingsData provider;

  public InstallationConfiguration(Environment environment) {
    var values = new HashMap<String, String>();
    var mail = List.of("HOST", "USERNAME", "PASSWORD", "FROM");
    boolean email =
        mail.stream().anyMatch(name -> !value(environment, "BLOT_SMTP_" + name).isEmpty());
    if (email) {
      for (String name : mail)
        values.put(
            "smtp." + name.toLowerCase(Locale.ROOT), required(environment, "BLOT_SMTP_" + name));
      int port = number(environment, "BLOT_SMTP_PORT", 587);
      if (port < 1 || port > 65535) throw invalid("BLOT_SMTP_PORT должен быть в диапазоне 1–65535");
      values.put("smtp.port", Integer.toString(port));
    }
    String key = value(environment, "BLOT_GIGACHAT_AUTH_KEY");
    if (!key.isEmpty()) {
      if (!key.matches("[A-Za-z0-9+/]+={0,2}") || key.length() > 4096)
        throw invalid("BLOT_GIGACHAT_AUTH_KEY: нужен Authorization Key без префикса Basic");
      values.put("provider.key", key);
      provider =
          new ProviderSettingsData(
              required(environment, "BLOT_GIGACHAT_MODEL"),
              number(environment, "BLOT_GIGACHAT_CONTEXT_TOKENS", 32768),
              number(environment, "BLOT_GIGACHAT_OUTPUT_TOKENS", 4096),
              count(environment, "BLOT_RUN_TOKEN_BUDGET", 1000000));
      try {
        ProviderSettingsService.validate(provider);
      } catch (RuntimeException failure) {
        throw invalid("Проверьте модель и лимиты BLOT_GIGACHAT_* / BLOT_RUN_TOKEN_BUDGET");
      }
      String certificate = value(environment, "BLOT_GIGACHAT_CA_FILE");
      if (!certificate.isEmpty()) values.put("provider.ca", certificate(certificate));
    } else {
      provider = null;
      if (!value(environment, "BLOT_GIGACHAT_CA_FILE").isEmpty())
        throw invalid("Для BLOT_GIGACHAT_CA_FILE также нужен BLOT_GIGACHAT_AUTH_KEY");
    }
    secrets = Map.copyOf(values);
  }

  public boolean emailManaged() {
    return secrets.containsKey("smtp.host");
  }

  public boolean providerManaged() {
    return provider != null;
  }

  public Map<String, String> secrets() {
    return secrets;
  }

  public ProviderSettingsData provider() {
    return provider;
  }

  private String certificate(String filename) {
    try {
      Path path = Path.of(filename);
      if (!path.isAbsolute()) throw invalid("BLOT_GIGACHAT_CA_FILE должен быть абсолютным путём");
      if (!Files.isRegularFile(path) || Files.size(path) > 65536)
        throw invalid("BLOT_GIGACHAT_CA_FILE: нужен PEM-файл размером до 64 KiB");
      String pem = Files.readString(path);
      new PemCertificates().inspect(pem);
      return pem;
    } catch (IOException | dev.blot.application.workspace.WorkspaceFailure failure) {
      throw invalid("Не удалось прочитать сертификат BLOT_GIGACHAT_CA_FILE");
    }
  }

  private String value(Environment environment, String name) {
    return environment.getProperty(name, "");
  }

  private String required(Environment environment, String name) {
    String value = value(environment, name);
    if (value.isBlank()) throw invalid("Заполните " + name + " в .env");
    return value;
  }

  private int number(Environment environment, String name, int fallback) {
    try {
      return Math.toIntExact(count(environment, name, fallback));
    } catch (ArithmeticException failure) {
      throw invalid("Слишком большое число: " + name);
    }
  }

  private long count(Environment environment, String name, long fallback) {
    String value = value(environment, name);
    try {
      return value.isEmpty() ? fallback : Long.parseLong(value);
    } catch (NumberFormatException failure) {
      throw invalid("Нужно целое число: " + name);
    }
  }

  private IllegalArgumentException invalid(String message) {
    return new IllegalArgumentException(message);
  }
}
