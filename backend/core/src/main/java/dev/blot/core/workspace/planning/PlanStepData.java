package dev.blot.core.workspace.planning;

public record PlanStepData(
    String key,
    String title,
    java.util.List<String> criteria,
    java.util.List<String> dependencies,
    String role,
    java.util.List<String> paths) {
  public PlanStepData {
    criteria = criteria == null ? null : java.util.List.copyOf(criteria);
    dependencies = dependencies == null ? null : java.util.List.copyOf(dependencies);
    paths = paths == null ? null : java.util.List.copyOf(paths);
  }
}
