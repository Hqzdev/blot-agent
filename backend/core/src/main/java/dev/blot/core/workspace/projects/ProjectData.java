package dev.blot.core.workspace.projects;

public record ProjectData(
    String name, String repositoryPath, String baseSha, String defaultBranch, boolean archived) {}
