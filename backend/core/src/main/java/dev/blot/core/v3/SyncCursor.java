package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record SyncCursor(
    RecordMetadata metadata,
    UUID deviceId,
    long sequence) {
  public SyncCursor {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(deviceId, "deviceId");
    if (sequence < 0) throw new IllegalArgumentException("sequence must be nonnegative");
  }
}
