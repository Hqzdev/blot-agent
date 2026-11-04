package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record AgentProfile(
    RecordMetadata metadata,
    String name,
    String roleId,
    String avatarShape,
    String avatarColor,
    String instructions,
    String modelId,
    AccessMode accessMode,
    UUID configurationId) {
  public AgentProfile {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(roleId, "roleId");
    Objects.requireNonNull(avatarShape, "avatarShape");
    Objects.requireNonNull(avatarColor, "avatarColor");
    Objects.requireNonNull(instructions, "instructions");
    Objects.requireNonNull(modelId, "modelId");
    Objects.requireNonNull(accessMode, "accessMode");
  }
}
