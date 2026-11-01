package dev.blot.core.workspace.agent;

import java.util.UUID;

public record AgentSessionData(
    String role,
    String instruction,
    UUID taskId,
    UUID conversationId,
    UUID parentSessionId,
    int depth,
    String workspace,
    String status,
    String waitingReason,
    int turns) {}
