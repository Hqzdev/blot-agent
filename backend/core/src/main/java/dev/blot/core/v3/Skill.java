package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Skill(
    RecordMetadata metadata,
    String name,
    UUID activeRevisionId,
    boolean archived) {
  public Skill {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(activeRevisionId, "activeRevisionId");
  }
}
