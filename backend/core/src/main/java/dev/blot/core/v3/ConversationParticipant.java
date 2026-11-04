package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ConversationParticipant(
    RecordMetadata metadata,
    UUID conversationId,
    UUID participantId,
    ParticipantKind kind,
    boolean removed) {
  public ConversationParticipant {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(participantId, "participantId");
    Objects.requireNonNull(kind, "kind");
  }
}
