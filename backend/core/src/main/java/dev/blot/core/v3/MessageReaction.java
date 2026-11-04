package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record MessageReaction(
    RecordMetadata metadata, UUID messageId, UUID participantId, String emoji, boolean removed) {
  public MessageReaction {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(messageId, "messageId");
    Objects.requireNonNull(participantId, "participantId");
    Objects.requireNonNull(emoji, "emoji");
  }
}
