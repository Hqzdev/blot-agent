package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record SkillRevision(
    RecordMetadata metadata,
    UUID skillId,
    String instructions,
    String parametersJSON,
    List<String> toolIds) {
  public SkillRevision {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(skillId, "skillId");
    Objects.requireNonNull(instructions, "instructions");
    Objects.requireNonNull(parametersJSON, "parametersJSON");
    Objects.requireNonNull(toolIds, "toolIds");
    toolIds = List.copyOf(toolIds);
  }
}
