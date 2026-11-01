package dev.blot.core.workspace.planning;

public record PlanData(
    java.util.List<PlanStepData> steps,
    long requirementsVersion,
    boolean approved,
    java.util.List<RequirementData> requirements,
    java.util.List<CoverageData> coverage) {
  public PlanData {
    steps = steps == null ? null : java.util.List.copyOf(steps);
    requirements = requirements == null ? null : java.util.List.copyOf(requirements);
    coverage = coverage == null ? null : java.util.List.copyOf(coverage);
  }
}
