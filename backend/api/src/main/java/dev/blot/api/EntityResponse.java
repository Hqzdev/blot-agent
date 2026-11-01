package dev.blot.api;

import dev.blot.core.*;
import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.SpecificationRevision;
import dev.blot.core.Task;
import java.util.List;
import java.util.Map;

/** Explicit transport projection; SQL models and platform Path never reach the serializer. */
final class EntityResponse {
  private EntityResponse() {}

  static Object from(Object value) {
    if (value instanceof Project p)
      return Map.of(
          "id",
          p.id().toString(),
          "name",
          p.name(),
          "repositoryPath",
          p.repositoryPath().toString(),
          "createdAt",
          p.createdAt().toString());
    if (value instanceof Run r)
      return Map.of(
          "id",
          r.id().toString(),
          "projectId",
          r.projectId().toString(),
          "goal",
          r.goal(),
          "createdAt",
          r.createdAt().toString(),
          "status",
          r.status().name(),
          "version",
          r.version());
    if (value instanceof SpecificationRevision r)
      return Map.of(
          "id",
          r.id().toString(),
          "runId",
          r.runId().toString(),
          "revision",
          r.revision(),
          "content",
          r.content(),
          "createdAt",
          r.createdAt().toString());
    if (value instanceof Task t)
      return Map.of(
          "id",
          t.id().toString(),
          "projectId",
          t.projectId().toString(),
          "runId",
          t.runId().toString(),
          "title",
          t.title(),
          "acceptanceCriteria",
          t.acceptanceCriteria(),
          "dependencyIds",
          t.dependencyIds().stream().map(Object::toString).sorted().toList(),
          "createdAt",
          t.createdAt().toString());
    if (value instanceof List<?> list) return list.stream().map(EntityResponse::from).toList();
    throw new IllegalArgumentException("Unsupported response type");
  }
}
