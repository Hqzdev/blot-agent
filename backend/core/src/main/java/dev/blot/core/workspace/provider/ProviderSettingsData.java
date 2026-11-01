package dev.blot.core.workspace.provider;

public record ProviderSettingsData(
    String model, int contextTokens, int outputTokens, long runTokenBudget) {}
