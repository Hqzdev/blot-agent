package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Artifact(
    RecordMetadata metadata,
    ExecutionContext execution,
    String name,
    String mediaType,
    long byteCount,
    String hash,
    String relativePath,
    Long encryptionEpoch) {
  public Artifact {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(mediaType, "mediaType");
    if (byteCount < 0) throw new IllegalArgumentException("byteCount must be nonnegative");
    Objects.requireNonNull(hash, "hash");
    Objects.requireNonNull(relativePath, "relativePath");
    if (encryptionEpoch != null && encryptionEpoch < 0) throw new IllegalArgumentException("encryptionEpoch must be nonnegative");
  }
}
