package dev.blot.api.workspace.installation;

import dev.blot.core.workspace.provider.ProviderSettingsData;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public final class SetupController {
  public record Status(
      boolean emailManaged, boolean providerManaged, ProviderSettingsData modelSettings) {}

  private final InstallationConfiguration configuration;

  public SetupController(InstallationConfiguration configuration) {
    this.configuration = configuration;
  }

  /** Возвращаем только режим работы и параметры модели, никогда ключи, SMTP или путь к .env. */
  @GetMapping("/v2/setup/status")
  public Status status() {
    return new Status(
        configuration.emailManaged(), configuration.providerManaged(), configuration.provider());
  }
}
