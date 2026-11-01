package dev.blot.core.workspace.projects;

import java.util.*;

public record TaskData(
    String title,
    List<String> criteria,
    List<UUID> dependencies,
    String role,
    List<String> paths,
    String status,
    UUID authorSessionId,
    UUID artifactId,
    UUID parentSessionId,
    long requirementsVersion) {
  public TaskData {
    criteria = criteria == null ? null : java.util.List.copyOf(criteria);
    dependencies = dependencies == null ? null : java.util.List.copyOf(dependencies);
    paths = paths == null ? null : java.util.List.copyOf(paths);
  }

  public TaskData(
      String title,
      List<String> criteria,
      List<UUID> deps,
      String role,
      List<String> paths,
      String status,
      UUID author,
      UUID artifact,
      UUID parent) {
    this(title, criteria, deps, role, paths, status, author, artifact, parent, 1);
  }

  public TaskData atRevision(long revision) {
    return new TaskData(
        title,
        criteria,
        dependencies,
        role,
        paths,
        status,
        authorSessionId,
        artifactId,
        parentSessionId,
        revision);
  }

  public long revision() {
    return requirementsVersion == 0 ? 1 : requirementsVersion;
  }

  public TaskData(
      String title,
      List<String> criteria,
      List<UUID> deps,
      String role,
      List<String> paths,
      String status,
      UUID author,
      UUID artifact) {
    this(title, criteria, deps, role, paths, status, author, artifact, null, 1);
  }
}
