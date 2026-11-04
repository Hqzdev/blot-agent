package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record ExecutionLease(
    RecordMetadata metadata,
    UUID taskId,
    UUID executorDeviceId,
    long generation,
    Instant expiresAt,
    LeaseState state) {
  public ExecutionLease {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(taskId, "taskId");
    Objects.requireNonNull(executorDeviceId, "executorDeviceId");
    if (generation < 0) throw new IllegalArgumentException("generation must be nonnegative");
    Objects.requireNonNull(expiresAt, "expiresAt");
    Objects.requireNonNull(state, "state");
  }
}
