package dev.blot.core.v3;

import java.util.Objects;
import java.util.UUID;

public record BudgetLedger(
    RecordMetadata metadata,
    ExecutionContext execution,
    UUID requestId,
    long reservedTokens,
    Long actualTokens,
    BudgetState state) {
  public BudgetLedger {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(execution, "execution");
    Objects.requireNonNull(requestId, "requestId");
    if (reservedTokens < 0)
      throw new IllegalArgumentException("reservedTokens must be nonnegative");
    if (actualTokens != null && actualTokens < 0)
      throw new IllegalArgumentException("actualTokens must be nonnegative");
    Objects.requireNonNull(state, "state");
  }
}
