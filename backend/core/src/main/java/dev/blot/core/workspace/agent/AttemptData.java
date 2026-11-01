package dev.blot.core.workspace.agent;

import java.util.UUID;

public record AttemptData(
    UUID sessionId, int number, String baseSha, String status, UUID artifactId, String error) {}
