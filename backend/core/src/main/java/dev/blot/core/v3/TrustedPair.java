package dev.blot.core.v3;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

public record TrustedPair(
    RecordMetadata metadata,
    UUID desktopDeviceId,
    UUID phoneDeviceId,
    String verificationCode,
    Instant expiresAt,
    TrustState state) {
  public TrustedPair {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(desktopDeviceId, "desktopDeviceId");
    Objects.requireNonNull(phoneDeviceId, "phoneDeviceId");
    Objects.requireNonNull(verificationCode, "verificationCode");
    Objects.requireNonNull(expiresAt, "expiresAt");
    Objects.requireNonNull(state, "state");
  }
}
