package dev.blot.application.workspace.requirements;

import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.planning.CoverageData;
import dev.blot.core.workspace.planning.PlanStepData;
import dev.blot.core.workspace.planning.RequirementData;
import java.util.*;

/** Проверяет связи структурированных требований с задачами принятого плана. */
public final class RequirementCoverage {
  public void validate(
      List<PlanStepData> steps, List<RequirementData> requirements, List<CoverageData> coverage) {
    if (requirements == null
        || requirements.isEmpty()
        || requirements.size() > 100
        || coverage == null)
      throw WorkspaceFailure.invalid("Нужны структурированные требования и их покрытие задачами");
    var requirementKeys = new HashSet<String>();
    for (var requirement : requirements) {
      Records.text(requirement.key(), "requirement.key", 100);
      Records.text(requirement.content(), "requirement.content", 4000);
      if (!requirementKeys.add(requirement.key()))
        throw WorkspaceFailure.invalid("Повтор ключа требования");
    }
    var taskKeys = new HashSet<String>();
    for (var step : steps) taskKeys.add(step.key());
    var covered = new HashSet<String>();
    for (var relation : coverage) {
      if (!requirementKeys.contains(relation.requirementKey())
          || !covered.add(relation.requirementKey())
          || relation.taskKeys() == null
          || relation.taskKeys().isEmpty()
          || !taskKeys.containsAll(relation.taskKeys()))
        throw WorkspaceFailure.invalid("Неверная связь требования с задачами");
    }
    if (!covered.equals(requirementKeys))
      throw WorkspaceFailure.invalid("Не все требования покрыты задачами");
  }
}
