package dev.blot.core.workspace.execution;

import java.util.UUID;

public record PreparedActionData(
    String capability,
    UUID sessionId,
    UUID taskId,
    String baseSha,
    java.util.Map<String, Object> arguments,
    String hash,
    String status) {}
