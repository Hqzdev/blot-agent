package dev.blot.core.workspace.conversation;

import java.util.UUID;

public record SummaryData(
    UUID conversationId,
    long throughOrdinal,
    String content,
    java.util.List<UUID> memoryIds,
    boolean valid) {
  public SummaryData {
    memoryIds = memoryIds == null ? null : java.util.List.copyOf(memoryIds);
  }
}
