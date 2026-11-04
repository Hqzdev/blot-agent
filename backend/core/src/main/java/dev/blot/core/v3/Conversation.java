package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record Conversation(
    RecordMetadata metadata,
    UUID agentId,
    String title,
    boolean mobileOwned,
    boolean pinned,
    boolean archived,
    ConversationKind kind) {
  public Conversation {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(title, "title");
  }
}
