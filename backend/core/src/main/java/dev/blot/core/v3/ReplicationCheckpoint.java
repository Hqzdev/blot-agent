package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ReplicationCheckpoint(
    RecordMetadata metadata, UUID deviceId, UUID streamId, long sequence, ReplicationState state) {
  public ReplicationCheckpoint {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(deviceId, "deviceId");
    Objects.requireNonNull(streamId, "streamId");
    if (sequence < 0) throw new IllegalArgumentException("sequence must be nonnegative");
    Objects.requireNonNull(state, "state");
  }
}
