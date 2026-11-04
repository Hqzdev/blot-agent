package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ExecutionContext(
    UUID executorDeviceId, UUID originDeviceId, UUID taskId, long revision, Long leaseGeneration) {
  public ExecutionContext {
    Objects.requireNonNull(executorDeviceId, "executorDeviceId");
    Objects.requireNonNull(originDeviceId, "originDeviceId");
    Objects.requireNonNull(taskId, "taskId");
    if (revision < 0) throw new IllegalArgumentException("revision must be nonnegative");
    if (leaseGeneration != null && leaseGeneration < 0)
      throw new IllegalArgumentException("leaseGeneration must be nonnegative");
  }
}
