package dev.blot.application.workspace.agent;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.WorkspacePaths;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.artifact.ArtifactData;
import dev.blot.core.workspace.execution.ToolOperationData;
import dev.blot.core.workspace.projects.TaskData;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Проверяет фактические пути и читает файлы только в области назначения. */
public final class AgentFiles {
  private final WorkspaceStore store;
  private final TokenGenerator tokens;
  private final ArtifactStore artifacts;
  private final Records records;

  public AgentFiles(
      WorkspaceStore store, TokenGenerator tokens, ArtifactStore artifacts, Records records) {
    this.store = store;
    this.tokens = tokens;
    this.artifacts = artifacts;
    this.records = records;
  }

  public Object read(Entity<AgentSessionData> s, Map<String, Object> a) {
    Path path = path(s, required(a, "path"), false);
    try {
      if (Files.size(path) > 262144)
        throw WorkspaceFailure.invalid("Файл слишком большой; используйте поиск");
      String content = Files.readString(path);
      recordRead(
          s,
          "project.read.file",
          Map.of("path", a.get("path"), "hash", hash(path), "bytes", Files.size(path)));
      return Map.of("path", a.get("path"), "content", content);
    } catch (java.io.IOException e) {
      throw WorkspaceFailure.invalid("Файл недоступен или не является UTF-8");
    }
  }

  public Object search(Entity<AgentSessionData> s, Map<String, Object> a) {
    String query = Records.text(required(a, "query"), "query", 1000);
    Path root = Path.of(s.data().workspace());
    var found = new ArrayList<Map<String, Object>>();
    try (var files = Files.walk(root)) {
      for (var p :
          files
              .filter(f -> Files.isRegularFile(f, LinkOption.NOFOLLOW_LINKS))
              .limit(10000)
              .toList()) {
        if (found.size() >= 100) break;
        String relative = root.relativize(p).toString();
        if (relative.startsWith(".git") || relative.contains("/.git/")) continue;
        try {
          Path checked = path(s, relative, false);
          if (Files.size(checked) > 262144) continue;
          var lines = Files.readAllLines(checked);
          for (int i = 0; i < lines.size() && found.size() < 100; i++)
            if (lines.get(i).contains(query))
              found.add(
                  Map.of(
                      "path",
                      relative,
                      "line",
                      i + 1,
                      "text",
                      lines.get(i).substring(0, Math.min(1000, lines.get(i).length()))));
        } catch (WorkspaceFailure | java.io.IOException ignored) {
          /* Бинарные и недоступные файлы не входят в текстовый поиск. */
        }
      }
      recordRead(
          s,
          "project.search",
          Map.of(
              "matches",
              found.size(),
              "paths",
              found.stream().map(row -> row.get("path")).distinct().toList()));
      return found;
    } catch (java.io.IOException e) {
      throw WorkspaceFailure.invalid("Поиск недоступен");
    }
  }

  public Path path(Entity<AgentSessionData> s, String relative, boolean writing) {
    try {
      Path root = Path.of(s.data().workspace()).toRealPath();
      Path raw = Path.of(relative);
      if (raw.isAbsolute()) throw forbidden();
      Path p = root.resolve(raw).normalize();
      if (!p.startsWith(root) || p.equals(root)) throw forbidden();
      if (WorkspacePaths.containsGitMetadata(root.relativize(p))) throw forbidden();
      Path ancestor = p;
      while (!Files.exists(ancestor, LinkOption.NOFOLLOW_LINKS)) ancestor = ancestor.getParent();
      Path actualAncestor = ancestor.toRealPath();
      Path real = actualAncestor.resolve(ancestor.relativize(p));
      if (!real.startsWith(root) || Files.isSymbolicLink(p)) throw forbidden();
      if (WorkspacePaths.containsGitMetadata(root.relativize(real))) throw forbidden();
      if (!writing && !Files.isRegularFile(real, LinkOption.NOFOLLOW_LINKS))
        throw WorkspaceFailure.invalid("Файл не найден");
      var task =
          store.transact(
              tx ->
                  Records.require(
                      tx, EntityKind.TASK, s.ownerId(), s.data().taskId(), TaskData.class));
      boolean scoped =
          task.data().paths().stream()
              .anyMatch(
                  scope ->
                      scope.equals(".")
                          || root.relativize(real).equals(Path.of(scope).normalize())
                          || root.relativize(real).startsWith(Path.of(scope).normalize()));
      if (!scoped) throw forbidden();
      return real;
    } catch (java.io.IOException e) {
      throw WorkspaceFailure.invalid("Путь недоступен");
    }
  }

  public String hash(Path path) {
    try {
      if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) return "absent";
      if (Files.size(path) > 33_554_432)
        throw WorkspaceFailure.invalid("Файл слишком большой для изменения");
      return tokens.digest(Base64.getEncoder().encodeToString(Files.readAllBytes(path)));
    } catch (java.io.IOException e) {
      throw WorkspaceFailure.invalid("Файл недоступен");
    }
  }

  private static WorkspaceFailure forbidden() {
    return new WorkspaceFailure(403, "forbidden", "Инструмент выходит за назначенную область");
  }

  private static String required(Map<String, Object> a, String key) {
    Object value = a.get(key);
    if (!(value instanceof String s)) throw WorkspaceFailure.invalid("Нужно поле " + key);
    return s;
  }

  private void recordRead(Entity<AgentSessionData> session, String name, Object result) {
    store.transact(
        tx ->
            records.create(
                tx,
                EntityKind.TOOL_OPERATION,
                session.ownerId(),
                session.projectId(),
                session.id(),
                new ToolOperationData(session.id(), null, name, "FINISHED", result, null)));
  }

  public Object readArtifact(Entity<AgentSessionData> s, Map<String, Object> a) {
    UUID id = UUID.fromString(required(a, "artifactId"));
    var e =
        store.transact(
            tx -> Records.require(tx, EntityKind.ARTIFACT, s.ownerId(), id, ArtifactData.class));
    if (!Objects.equals(s.projectId(), e.projectId())) throw forbidden();
    int offset = a.get("offset") instanceof Number n ? n.intValue() : 0;
    return Map.of(
        "content",
        new String(
            artifacts.read(e.data().relativePath(), e.data().hash(), offset, 262144),
            StandardCharsets.UTF_8));
  }
}
