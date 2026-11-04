package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record McpConnection(
    RecordMetadata metadata,
    String name,
    String transport,
    String endpoint,
    List<String> toolIds,
    ConnectionState state) {
  public McpConnection {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(transport, "transport");
    Objects.requireNonNull(endpoint, "endpoint");
    Objects.requireNonNull(toolIds, "toolIds");
    toolIds = List.copyOf(toolIds);
    Objects.requireNonNull(state, "state");
  }
}
