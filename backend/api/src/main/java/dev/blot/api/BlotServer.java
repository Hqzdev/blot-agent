package dev.blot.api;

import dev.blot.infrastructure.workspace.configuration.DotenvFile;
import java.nio.file.Path;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class BlotServer {
  public static void main(String[] args) {
    var application = new SpringApplication(BlotServer.class);
    String file = System.getenv("BLOT_ENV_FILE");
    if ("1".equals(System.getenv("BLOT_ENV_STDIN"))) {
      application.setDefaultProperties(new DotenvFile().readEncoded(System.in));
    } else if (file != null && !file.isBlank()) {
      // Значения доступны уже при настройке логов; окружение и аргументы имеют приоритет.
      application.setDefaultProperties(new DotenvFile().read(Path.of(file)));
    }
    application.run(args);
  }
}
