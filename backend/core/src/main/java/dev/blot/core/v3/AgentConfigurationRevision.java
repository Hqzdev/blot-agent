package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record AgentConfigurationRevision(
    RecordMetadata metadata,
    UUID agentId,
    long revision,
    String instructions,
    List<String> toolIds,
    String modelId) {
  public AgentConfigurationRevision {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(agentId, "agentId");
    if (revision < 0) throw new IllegalArgumentException("revision must be nonnegative");
    Objects.requireNonNull(instructions, "instructions");
    Objects.requireNonNull(toolIds, "toolIds");
    toolIds = List.copyOf(toolIds);
    Objects.requireNonNull(modelId, "modelId");
  }
}
