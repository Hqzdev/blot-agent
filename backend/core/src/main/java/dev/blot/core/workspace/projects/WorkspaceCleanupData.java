package dev.blot.core.workspace.projects;

import java.util.UUID;

/** Задание остаётся после удаления проекта, пока рабочая область не очищена. */
public record WorkspaceCleanupData(
    UUID projectId, UUID runId, String repositoryPath, String status, String error) {}
