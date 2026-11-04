package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Assignment(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID stepId,
    UUID agentId,
    AssignmentState state,
    List<UUID> dependencyIds) {
  public Assignment {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(stepId, "stepId");
    Objects.requireNonNull(agentId, "agentId");
    Objects.requireNonNull(state, "state");
    Objects.requireNonNull(dependencyIds, "dependencyIds");
    dependencyIds = List.copyOf(dependencyIds);
  }
}
