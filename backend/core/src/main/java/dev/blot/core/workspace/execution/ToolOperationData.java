package dev.blot.core.workspace.execution;

import java.util.UUID;

public record ToolOperationData(
    UUID sessionId,
    UUID preparedActionId,
    String name,
    String status,
    Object result,
    String error) {}
