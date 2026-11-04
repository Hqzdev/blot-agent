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
    UUID deviceId) {
  public Connection {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(service, "service");
    Objects.requireNonNull(accountName, "accountName");
    Objects.requireNonNull(scopes, "scopes");
    scopes = List.copyOf(scopes);
    Objects.requireNonNull(state, "state");
  }
}
