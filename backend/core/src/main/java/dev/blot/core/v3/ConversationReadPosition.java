package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record ConversationReadPosition(
    RecordMetadata metadata,
    UUID conversationId,
    UUID participantId,
    UUID messageId,
    long position) {
  public ConversationReadPosition {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(participantId, "participantId");
    Objects.requireNonNull(messageId, "messageId");
    if (position < 0) throw new IllegalArgumentException("position must be nonnegative");
  }
}
