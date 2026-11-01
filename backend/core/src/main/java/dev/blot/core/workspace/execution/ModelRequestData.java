package dev.blot.core.workspace.execution;

import java.util.UUID;

public record ModelRequestData(
    String model,
    String purpose,
    int priority,
    String status,
    UUID runId,
    UUID sessionId,
    Long inputTokens,
    Long outputTokens,
    String error) {}
