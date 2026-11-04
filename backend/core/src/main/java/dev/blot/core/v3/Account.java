package dev.blot.core.v3;

import java.util.Objects;

public record Account(RecordMetadata metadata, String email, String name, boolean emailVerified) {
  public Account {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(email, "email");
    Objects.requireNonNull(name, "name");
  }
}
