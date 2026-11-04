package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ToolInvocation(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID preparedActionId,
    ActionState state,
    String externalId,
    String result,
    Integer exitCode) {
  public ToolInvocation {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(preparedActionId, "preparedActionId");
    Objects.requireNonNull(state, "state");
  }
}
