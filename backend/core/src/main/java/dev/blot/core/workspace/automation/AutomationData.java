package dev.blot.core.workspace.automation;

public record AutomationData(
    String name,
    String goal,
    String timezone,
    String localTime,
    java.util.List<Integer> weekdays,
    java.time.Instant nextAt,
    java.time.Instant lastScheduledAt,
    boolean enabled,
    long tokenBudget) {
  public AutomationData {
    weekdays = weekdays == null ? null : java.util.List.copyOf(weekdays);
  }
}
