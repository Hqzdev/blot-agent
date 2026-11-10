package dev.blot.api.workspace.v3;

import dev.blot.application.ports.*;
import dev.blot.application.workspace.v3.*;
import dev.blot.infrastructure.workspace.database.SqliteV3Store;
import java.nio.file.Path;
import java.time.Clock;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;

@Configuration
public class V3Configuration {
  @Bean
  V3Store v3Store(@Value("${blot.database:blot.db}") String database, JsonCodec json) {
    return new SqliteV3Store(Path.of(database + ".v3.db"), json);
  }

  @Bean
  V3Workspace v3Workspace(V3Store store, JsonCodec json, Clock clock) {
    return new V3Workspace(store, json, clock);
  }

  @Bean(destroyMethod = "close")
  @ConditionalOnProperty(
      name = "blot.v3.worker.enabled",
      havingValue = "true",
      matchIfMissing = true)
  V3ChatWorker v3ChatWorker(
      V3Store store, V3Workspace workspace, JsonCodec json, ProviderGateway provider) {
    return new V3ChatWorker(store, workspace, json, provider);
  }
}
