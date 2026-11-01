package dev.blot.core.workspace.projects;

import java.util.UUID;

public record RunData(
    String goal, String status, UUID planId, long requirementsVersion, String waitingReason) {}
