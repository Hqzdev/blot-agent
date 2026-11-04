package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record RecordChange(
    RecordMetadata metadata,
    UUID originDeviceId,
    long sequence,
    String recordKind,
    UUID recordId,
    long baseVersion,
    long recordVersion,
    ChangeOperation operation,
    String payloadJSON) {
  public RecordChange {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(originDeviceId, "originDeviceId");
    if (sequence < 0) throw new IllegalArgumentException("sequence must be nonnegative");
    Objects.requireNonNull(recordKind, "recordKind");
    Objects.requireNonNull(recordId, "recordId");
    if (baseVersion < 0) throw new IllegalArgumentException("baseVersion must be nonnegative");
    if (recordVersion < 0) throw new IllegalArgumentException("recordVersion must be nonnegative");
    Objects.requireNonNull(operation, "operation");
  }
}
