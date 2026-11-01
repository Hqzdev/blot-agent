package dev.blot.core.workspace.conversation;

import java.util.UUID;

public record ConversationData(
    String title, String mode, UUID runId, boolean archived, long requirementsVersion) {
  public ConversationData(String title, String mode, UUID runId, boolean archived) {
    this(title, mode, runId, archived, 0);
  }

  public ConversationData forRequirements(long revision) {
    return new ConversationData(title, mode, runId, archived, revision);
  }
}
