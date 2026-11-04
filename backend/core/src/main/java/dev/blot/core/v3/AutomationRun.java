package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

public record AutomationRun(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID automationId,
    Instant scheduledAt,
    TaskState state,
    AutomationTrigger trigger) {
  public AutomationRun {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(automationId, "automationId");
    Objects.requireNonNull(scheduledAt, "scheduledAt");
    Objects.requireNonNull(state, "state");
  }
}
