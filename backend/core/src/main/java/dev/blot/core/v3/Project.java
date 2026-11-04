package dev.blot.core.v3;

import java.util.Objects;

public record Project(RecordMetadata metadata, String name, String repositoryPath) {
  public Project {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(repositoryPath, "repositoryPath");
  }
}
