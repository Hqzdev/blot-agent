package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record AgentMessage(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID senderSessionId,
    UUID recipientSessionId,
    String content) {
  public AgentMessage {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(senderSessionId, "senderSessionId");
    Objects.requireNonNull(recipientSessionId, "recipientSessionId");
    Objects.requireNonNull(content, "content");
  }
}
