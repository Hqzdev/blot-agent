package dev.blot.core.workspace.artifact;

import java.util.UUID;

public record ArtifactData(
    String hash,
    String mediaType,
    String relativePath,
    String baseSha,
    UUID authorSessionId,
    UUID taskId) {}
