package dev.blot.core.workspace.agent;

import java.util.UUID;

public record AssignmentData(UUID taskId, UUID sessionId, String role, String reason) {}
