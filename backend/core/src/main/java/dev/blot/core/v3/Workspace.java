package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Workspace(
    RecordMetadata metadata,
    String name,
    UUID executorDeviceId,
    AccessMode accessMode,
    List<UUID> folderIds) {
  public Workspace {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(accessMode, "accessMode");
    Objects.requireNonNull(folderIds, "folderIds");
    folderIds = List.copyOf(folderIds);
  }
}
