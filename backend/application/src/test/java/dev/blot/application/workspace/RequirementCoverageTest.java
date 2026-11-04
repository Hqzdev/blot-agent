package dev.blot.application.workspace;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.workspace.requirements.RequirementCoverage;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.planning.CoverageData;
import dev.blot.core.workspace.planning.PlanData;
import dev.blot.core.workspace.planning.PlanStepData;
import dev.blot.core.workspace.planning.RequirementData;
import java.util.*;
import org.junit.jupiter.api.Test;

class RequirementCoverageTest {
  @Test
  void everyDeclaredRequirementNeedsAnExistingTask() {
    var validator = new RequirementCoverage();
    var steps =
        List.of(
            new PlanStepData(
                "a", "Implement", List.of("Works"), List.of(), "BACKEND", List.of(".")));
    var requirements =
        List.of(
            new RequirementData("r1", "Preserve data"), new RequirementData("r2", "Return result"));
    assertThrows(
        WorkspaceFailure.class,
        () ->
            validator.validate(steps, requirements, List.of(new CoverageData("r1", List.of("a")))));
    assertThrows(
        WorkspaceFailure.class,
        () ->
            validator.validate(
                steps,
                requirements,
                List.of(
                    new CoverageData("r1", List.of("unknown")),
                    new CoverageData("r2", List.of("a")))));
    assertDoesNotThrow(
        () ->
            validator.validate(
                steps,
                requirements,
                List.of(
                    new CoverageData("r1", List.of("a")), new CoverageData("r2", List.of("a")))));
  }

  @Test
  void planOwnsImmutableCopiesOfItsLists() {
    var steps = new ArrayList<PlanStepData>();
    steps.add(
        new PlanStepData("a", "Implement", List.of("Works"), List.of(), "BACKEND", List.of(".")));
    var plan =
        new PlanData(
            steps,
            1,
            false,
            List.of(new RequirementData("r1", "Result")),
            List.of(new CoverageData("r1", List.of("a"))));
    steps.clear();
    assertEquals(1, plan.steps().size());
    assertThrows(UnsupportedOperationException.class, () -> plan.steps().clear());
  }
}
