package dev.blot.core.v3;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record Automation(
    RecordMetadata metadata,
    AutomationKind kind,
    UUID executorDeviceId,
    UUID agentId,
    String name,
    String goal,
    String timezone,
    String localTime,
    List<Long> weekdays,
    MissedRunPolicy missedRunPolicy,
    boolean enabled,
    UUID skillRevisionId,
    Instant scheduledAt,
    Long maxCatchUpRuns) {
  public Automation {
    Objects.requireNonNull(metadata, "metadata");
    Objects.requireNonNull(kind, "kind");
    Objects.requireNonNull(name, "name");
    Objects.requireNonNull(goal, "goal");
    Objects.requireNonNull(timezone, "timezone");
    Objects.requireNonNull(localTime, "localTime");
    Objects.requireNonNull(weekdays, "weekdays");
    weekdays = List.copyOf(weekdays);
    Objects.requireNonNull(missedRunPolicy, "missedRunPolicy");
    if (maxCatchUpRuns != null && maxCatchUpRuns < 0) throw new IllegalArgumentException("maxCatchUpRuns must be nonnegative");
  }
}
