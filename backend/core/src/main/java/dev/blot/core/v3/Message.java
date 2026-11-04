package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Message(
    RecordMetadata metadata,
    UUID conversationId,
    MessageRole role,
    String content,
    DeliveryState delivery,
    UUID commandId,
    List<UUID> artifactIds,
    UUID authorAgentId,
    UUID replyToMessageId,
    List<MessageMention> mentions,
    Long position,
    UUID executorDeviceId) {
  public Message {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(role, "role");
    Objects.requireNonNull(content, "content");
    Objects.requireNonNull(delivery, "delivery");
    Objects.requireNonNull(commandId, "commandId");
    Objects.requireNonNull(artifactIds, "artifactIds");
    artifactIds = List.copyOf(artifactIds);
    mentions = mentions == null ? null : List.copyOf(mentions);
    if (position != null && position < 0)
      throw new IllegalArgumentException("position must be nonnegative");
  }
}
