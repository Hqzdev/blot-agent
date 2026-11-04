package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Project(
    RecordMetadata metadata,
    String name,
    String repositoryPath) {
  public Project {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(repositoryPath, "repositoryPath");
  }
}
