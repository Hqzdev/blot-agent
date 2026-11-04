package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record ApprovalGrant(
    RecordMetadata metadata,
    GrantKind kind,
    UUID actionId,
    String operationClass,
    String scope,
    String resource,
    String digest,
    Instant expiresAt,
    boolean revoked) {
  public ApprovalGrant {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(kind, "kind");
    Objects.requireNonNull(operationClass, "operationClass");
    Objects.requireNonNull(scope, "scope");
    Objects.requireNonNull(resource, "resource");
  }
}
