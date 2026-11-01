package dev.blot.infrastructure.database;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.blot.core.*;
import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.RunStatus;
import dev.blot.core.SpecificationRevision;
import dev.blot.core.Task;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;

final class StorageCodec {
  private final ObjectMapper mapper = new ObjectMapper();

  String encode(Map<String, Object> value) {
    try {
      return mapper.writeValueAsString(value);
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  JsonNode decode(String value) {
    try {
      return mapper.readTree(value);
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  String encode(Project value) {
    return encode(
        Map.ofEntries(
            Map.entry("id", value.id().toString()),
            Map.entry("name", value.name()),
            Map.entry("repositoryPath", value.repositoryPath().toString()),
            Map.entry("createdAt", value.createdAt().toString())));
  }

  Project decodeProject(String data) {
    try {
      JsonNode n = decode(data);
      return new Project(
          UUID.fromString(n.get("id").asText()),
          n.get("name").asText(),
          Path.of(n.get("repositoryPath").asText()),
          Instant.parse(n.get("createdAt").asText()));
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  String encode(Run value) {
    return encode(
        Map.ofEntries(
            Map.entry("id", value.id().toString()),
            Map.entry("projectId", value.projectId().toString()),
            Map.entry("goal", value.goal()),
            Map.entry("createdAt", value.createdAt().toString()),
            Map.entry("status", value.status().toString()),
            Map.entry("version", value.version())));
  }

  Run decodeRun(String data) {
    try {
      JsonNode n = decode(data);
      return new Run(
          UUID.fromString(n.get("id").asText()),
          UUID.fromString(n.get("projectId").asText()),
          n.get("goal").asText(),
          Instant.parse(n.get("createdAt").asText()),
          RunStatus.valueOf(n.get("status").asText()),
          n.get("version").asLong());
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  String encode(SpecificationRevision value) {
    return encode(
        Map.ofEntries(
            Map.entry("id", value.id().toString()),
            Map.entry("runId", value.runId().toString()),
            Map.entry("revision", value.revision()),
            Map.entry("content", value.content()),
            Map.entry("createdAt", value.createdAt().toString())));
  }

  SpecificationRevision decodeSpecificationRevision(String data) {
    try {
      JsonNode n = decode(data);
      return new SpecificationRevision(
          UUID.fromString(n.get("id").asText()),
          UUID.fromString(n.get("runId").asText()),
          n.get("revision").asInt(),
          n.get("content").asText(),
          Instant.parse(n.get("createdAt").asText()));
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  String encode(Task value) {
    return encode(
        Map.ofEntries(
            Map.entry("id", value.id().toString()),
            Map.entry("projectId", value.projectId().toString()),
            Map.entry("runId", value.runId().toString()),
            Map.entry("title", value.title()),
            Map.entry("acceptanceCriteria", value.acceptanceCriteria()),
            Map.entry("dependencyIds", value.dependencyIds().stream().map(UUID::toString).toList()),
            Map.entry("createdAt", value.createdAt().toString())));
  }

  Task decodeTask(String data) {
    try {
      JsonNode n = decode(data);
      return new Task(
          UUID.fromString(n.get("id").asText()),
          UUID.fromString(n.get("projectId").asText()),
          UUID.fromString(n.get("runId").asText()),
          n.get("title").asText(),
          strings(n.get("acceptanceCriteria")),
          new HashSet<>(strings(n.get("dependencyIds")).stream().map(UUID::fromString).toList()),
          Instant.parse(n.get("createdAt").asText()));
    } catch (Exception e) {
      throw new StorageException(StorageException.Kind.CORRUPT_DATA, e);
    }
  }

  private List<String> strings(JsonNode node) {
    List<String> result = new ArrayList<>();
    node.forEach(n -> result.add(n.asText()));
    return result;
  }
}
