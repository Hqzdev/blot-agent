package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

public record RecordTombstone(
    RecordMetadata metadata,
    String recordKind,
    UUID recordId,
    UUID deletedByDeviceId,
    Instant deletedAt) {
  public RecordTombstone {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(recordKind, "recordKind");
    Objects.requireNonNull(recordId, "recordId");
    Objects.requireNonNull(deletedByDeviceId, "deletedByDeviceId");
    Objects.requireNonNull(deletedAt, "deletedAt");
  }
}
