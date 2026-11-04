package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Connection(
    RecordMetadata metadata,
    String service,
    String accountName,
    List<String> scopes,
    ConnectionState state,
    UUID deviceId,
    String pluginId,
    List<String> resourceIds,
    List<UUID> agentIds,
    List<String> allowedOperations) {
  public Connection(
      RecordMetadata metadata,
      String service,
      String accountName,
      List<String> scopes,
      ConnectionState state,
      UUID deviceId) {
    this(metadata, service, accountName, scopes, state, deviceId, null, null, null, null);
  }

  public Connection {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(service, "service");
    Objects.requireNonNull(accountName, "accountName");
    Objects.requireNonNull(scopes, "scopes");
    scopes = List.copyOf(scopes);
    Objects.requireNonNull(state, "state");
    resourceIds = resourceIds == null ? null : List.copyOf(resourceIds);
    agentIds = agentIds == null ? null : List.copyOf(agentIds);
    allowedOperations = allowedOperations == null ? null : List.copyOf(allowedOperations);
  }
}
