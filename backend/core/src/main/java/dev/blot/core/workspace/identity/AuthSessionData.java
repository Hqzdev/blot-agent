package dev.blot.core.workspace.identity;

import java.time.Instant;
import java.util.UUID;

public record AuthSessionData(
    String tokenHash, UUID deviceId, Instant expiresAt, boolean revoked) {}
