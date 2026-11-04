package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record MemoryEntry(
    RecordMetadata metadata,
    MemoryScope scope,
    UUID scopeId,
    String content,
    UUID sourceId,
    MemoryState state) {
  public MemoryEntry {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(scope, "scope");
    Objects.requireNonNull(content, "content");
    Objects.requireNonNull(sourceId, "sourceId");
    Objects.requireNonNull(state, "state");
  }
}
