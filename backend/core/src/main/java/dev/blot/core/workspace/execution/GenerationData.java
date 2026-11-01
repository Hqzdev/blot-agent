package dev.blot.core.workspace.execution;

import java.util.UUID;

public record GenerationData(
    UUID conversationId,
    UUID sessionId,
    String status,
    String error,
    Long inputTokens,
    Long outputTokens) {}
