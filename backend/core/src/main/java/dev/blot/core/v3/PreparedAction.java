package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

public record PreparedAction(
    RecordMetadata metadata,
    ExecutionContext execution,
    String toolId,
    String resource,
    String parameters,
    String digest,
    String consequences,
    Instant expiresAt,
    ActionState state,
    UUID preparationId) {
  public PreparedAction {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(toolId, "toolId");
    Objects.requireNonNull(resource, "resource");
    Objects.requireNonNull(parameters, "parameters");
    Objects.requireNonNull(digest, "digest");
    Objects.requireNonNull(consequences, "consequences");
    Objects.requireNonNull(expiresAt, "expiresAt");
    Objects.requireNonNull(state, "state");
  }
}
