package dev.blot.core.v3;

import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Task(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID projectId,
    UUID conversationId,
    String goal,
    TaskState state,
    List<String> plan,
    UUID configurationId,
    UUID parentTaskId,
    UUID skillRevisionId,
    Long budgetTokenLimit,
    ExecutionMode executionMode) {
  public Task {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(goal, "goal");
    Objects.requireNonNull(state, "state");
    Objects.requireNonNull(plan, "plan");
    plan = List.copyOf(plan);
    if (budgetTokenLimit != null && budgetTokenLimit < 0)
      throw new IllegalArgumentException("budgetTokenLimit must be nonnegative");
  }
}
