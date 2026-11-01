package dev.blot.core.workspace.identity;

import java.util.UUID;

/** Личность создаётся после проверки сессии, а не из тела команды. */
public record Actor(UUID accountId, UUID sessionId, UUID deviceId, boolean local) {}
