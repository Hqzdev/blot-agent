package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

public record ConversationCard(
    RecordMetadata metadata,
    UUID messageId,
    UUID operationId,
    UUID executorDeviceId,
    String kind,
    String state,
    Instant expiresAt,
    String payloadJSON,
    String responseJSON,
    UUID updatedByDeviceId) {
  public ConversationCard {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(messageId, "messageId");
    Objects.requireNonNull(operationId, "operationId");
    Objects.requireNonNull(executorDeviceId, "executorDeviceId");
    Objects.requireNonNull(kind, "kind");
    Objects.requireNonNull(state, "state");
    Objects.requireNonNull(payloadJSON, "payloadJSON");
    Objects.requireNonNull(updatedByDeviceId, "updatedByDeviceId");
  }
}
