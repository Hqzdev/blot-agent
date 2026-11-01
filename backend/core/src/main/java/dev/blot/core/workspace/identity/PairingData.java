package dev.blot.core.workspace.identity;

import java.time.Instant;
import java.util.UUID;

public record PairingData(
    String secretHash,
    Instant expiresAt,
    String deviceName,
    String platform,
    UUID deviceId,
    boolean approved,
    boolean claimed) {}
