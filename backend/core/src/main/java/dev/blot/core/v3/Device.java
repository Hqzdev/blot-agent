package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;

public record Device(
    RecordMetadata metadata,
    String name,
    DeviceKind kind,
    String platform,
    String publicKey,
    Instant lastSeenAt,
    boolean revoked) {
  public Device {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(kind, "kind");
    Objects.requireNonNull(platform, "platform");
    Objects.requireNonNull(publicKey, "publicKey");
  }
}
