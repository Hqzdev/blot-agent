package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record ContextSummary(
    RecordMetadata metadata,
    UUID conversationId,
    String content,
    List<UUID> sourceIds,
    boolean valid) {
  public ContextSummary {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(content, "content");
    Objects.requireNonNull(sourceIds, "sourceIds");
    sourceIds = List.copyOf(sourceIds);
  }
}
