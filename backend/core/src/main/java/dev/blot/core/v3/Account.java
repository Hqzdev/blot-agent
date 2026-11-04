package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Account(
    RecordMetadata metadata,
    String email,
    String name,
    boolean emailVerified) {
  public Account {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(email, "email");
    Objects.requireNonNull(name, "name");
  }
}
