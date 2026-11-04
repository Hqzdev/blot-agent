package dev.blot.cloud.identity;

import java.util.UUID;

public record CloudActor(
    UUID ownerID, UUID workspaceID, UUID sessionID, UUID deviceID, boolean bootstrapAllowed) {}
