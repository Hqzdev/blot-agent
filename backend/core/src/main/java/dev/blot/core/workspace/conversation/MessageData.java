package dev.blot.core.workspace.conversation;

import java.util.UUID;

public record MessageData(
    String role,
    String content,
    long ordinal,
    UUID generationId,
    String functionName,
    String functionStateId,
    Object functionCall) {
  public MessageData(
      String role, String content, long ordinal, UUID generationId, String name, String state) {
    this(role, content, ordinal, generationId, name, state, null);
  }
}
