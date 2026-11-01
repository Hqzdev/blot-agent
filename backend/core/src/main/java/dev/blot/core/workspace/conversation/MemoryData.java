package dev.blot.core.workspace.conversation;

import java.util.UUID;

public record MemoryData(
    String scope, UUID scopeId, String content, UUID sourceId, String status) {}
