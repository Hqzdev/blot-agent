package dev.blot.core.workspace.identity;

public record AccountData(
    String email, String passwordHash, boolean verified, String displayName) {}
