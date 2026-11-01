package dev.blot.core.workspace.conversation;

import java.util.UUID;

public record InboxData(
    UUID senderSessionId,
    UUID recipientSessionId,
    UUID taskId,
    String content,
    boolean processed,
    UUID invocationId) {
  public InboxData(UUID sender, UUID recipient, UUID task, String content, boolean processed) {
    this(sender, recipient, task, content, processed, null);
  }

  public InboxData markProcessed() {
    return new InboxData(senderSessionId, recipientSessionId, taskId, content, true, invocationId);
  }
}
