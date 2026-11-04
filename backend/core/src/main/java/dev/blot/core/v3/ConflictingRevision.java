package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ConflictingRevision(
    RecordMetadata metadata,
    String recordKind,
    UUID recordId,
    long baseVersion,
    UUID originDeviceId,
    String payloadJSON,
    boolean resolved) {
  public ConflictingRevision {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(recordKind, "recordKind");
    Objects.requireNonNull(recordId, "recordId");
    if (baseVersion < 0) throw new IllegalArgumentException("baseVersion must be nonnegative");
    Objects.requireNonNull(originDeviceId, "originDeviceId");
    Objects.requireNonNull(payloadJSON, "payloadJSON");
  }
}
