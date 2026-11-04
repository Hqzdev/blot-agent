package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record TaskAttempt(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID stepId,
    UUID agentId,
    AttemptState state,
    List<String> criteria) {
  public TaskAttempt {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(stepId, "stepId");
    Objects.requireNonNull(agentId, "agentId");
    Objects.requireNonNull(state, "state");
    Objects.requireNonNull(criteria, "criteria");
    criteria = List.copyOf(criteria);
  }
}
