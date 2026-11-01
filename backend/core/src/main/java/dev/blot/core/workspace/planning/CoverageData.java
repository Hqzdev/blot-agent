package dev.blot.core.workspace.planning;

public record CoverageData(String requirementKey, java.util.List<String> taskKeys) {
  public CoverageData {
    taskKeys = taskKeys == null ? null : java.util.List.copyOf(taskKeys);
  }
}
