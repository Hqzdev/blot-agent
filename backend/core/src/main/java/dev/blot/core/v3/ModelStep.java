package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record ModelStep(
    RecordMetadata metadata,
    UUID conversationId,
    UUID sourceMessageId,
    UUID responseMessageId,
    UUID taskId,
    UUID executorDeviceId,
    UUID originDeviceId,
    ExecutionMode executionMode,
    long stepIndex,
    String modelId,
    UUID configurationId,
    UUID skillRevisionId,
    long budgetTokenLimit,
    String requestJSON,
    String toolCallsJSON,
    String toolResultsJSON,
    Long inputTokens,
    Long outputTokens,
    ModelStepState state) {
  public ModelStep {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(conversationId, "conversationId");
    Objects.requireNonNull(sourceMessageId, "sourceMessageId");
    Objects.requireNonNull(responseMessageId, "responseMessageId");
    Objects.requireNonNull(executorDeviceId, "executorDeviceId");
    Objects.requireNonNull(originDeviceId, "originDeviceId");
    Objects.requireNonNull(executionMode, "executionMode");
    if (stepIndex < 0) throw new IllegalArgumentException("stepIndex must be nonnegative");
    Objects.requireNonNull(modelId, "modelId");
    if (budgetTokenLimit < 0)
      throw new IllegalArgumentException("budgetTokenLimit must be nonnegative");
    Objects.requireNonNull(requestJSON, "requestJSON");
    if (inputTokens != null && inputTokens < 0)
      throw new IllegalArgumentException("inputTokens must be nonnegative");
    if (outputTokens != null && outputTokens < 0)
      throw new IllegalArgumentException("outputTokens must be nonnegative");
    Objects.requireNonNull(state, "state");
  }
}
