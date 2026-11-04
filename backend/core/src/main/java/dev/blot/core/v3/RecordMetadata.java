package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record RecordMetadata(
    UUID id,
    UUID ownerId,
    UUID workspaceId,
    long version,
    Instant createdAt,
    Instant updatedAt) {
  public RecordMetadata {
    Objects.requireNonNull(id, "id");
    Objects.requireNonNull(ownerId, "ownerId");
    if (version < 0) throw new IllegalArgumentException("version must be nonnegative");
    Objects.requireNonNull(createdAt, "createdAt");
    Objects.requireNonNull(updatedAt, "updatedAt");
  }
}
