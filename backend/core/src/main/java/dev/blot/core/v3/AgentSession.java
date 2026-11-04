package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record AgentSession(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID agentId,
    UUID configurationId,
    UUID parentSessionId,
    SessionState state) {
  public AgentSession {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(agentId, "agentId");
    Objects.requireNonNull(configurationId, "configurationId");
    Objects.requireNonNull(state, "state");
  }
}
