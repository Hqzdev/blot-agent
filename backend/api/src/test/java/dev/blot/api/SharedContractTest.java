package dev.blot.api;

import com.fasterxml.jackson.databind.*;
import dev.blot.core.*;
import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.RunStatus;
import dev.blot.core.SpecificationRevision;
import dev.blot.core.Task;
import dev.blot.core.workspace.Entity;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class SharedContractTest {
  private record LegacyEnvelope(
      int schemaVersion,
      UUID commandId,
      String type,
      UUID projectId,
      Long expectedVersion,
      Map<String, Object> payload) {}

  private final ObjectMapper mapper = new ObjectMapper();

  private JsonNode fixture(String name) throws Exception {
    return mapper.readTree(Path.of(System.getProperty("blot.fixtures"), name + ".json").toFile());
  }

  private JsonNode projection(Object value) throws Exception {
    return mapper.readTree(mapper.writeValueAsString(value));
  }

  private UUID id(JsonNode n, String name) {
    return UUID.fromString(n.get(name).asText());
  }

  @Test
  void allDomainFixturesMatchHttpProjection() throws Exception {
    var p = fixture("domain-project");
    assertEquals(
        p,
        projection(
            EntityResponse.from(
                new Project(
                    id(p, "id"),
                    p.get("name").asText(),
                    Path.of(p.get("repositoryPath").asText()),
                    Instant.parse(p.get("createdAt").asText())))));
    var r = fixture("domain-run");
    assertEquals(
        r,
        projection(
            EntityResponse.from(
                new Run(
                    id(r, "id"),
                    id(r, "projectId"),
                    r.get("goal").asText(),
                    Instant.parse(r.get("createdAt").asText()),
                    RunStatus.valueOf(r.get("status").asText()),
                    r.get("version").asLong()))));
    var s = fixture("domain-specification");
    assertEquals(
        s,
        projection(
            EntityResponse.from(
                new SpecificationRevision(
                    id(s, "id"),
                    id(s, "runId"),
                    s.get("revision").asInt(),
                    s.get("content").asText(),
                    Instant.parse(s.get("createdAt").asText())))));
    var t = fixture("domain-task");
    assertEquals(
        t,
        projection(
            EntityResponse.from(
                new Task(
                    id(t, "id"),
                    id(t, "projectId"),
                    id(t, "runId"),
                    t.get("title").asText(),
                    List.of("Done"),
                    Set.of(),
                    Instant.parse(t.get("createdAt").asText())))));
  }

  @Test
  void everyCommandAndErrorHasCompatibleEnvelope() throws Exception {
    for (String name :
        List.of(
            "command-project-create",
            "command-create-run",
            "command-run-status",
            "command-specification-create",
            "command-task-create")) {
      var c = mapper.treeToValue(fixture(name), LegacyEnvelope.class);
      assertEquals(1, c.schemaVersion());
      assertNotNull(c.commandId());
      assertNotNull(c.payload());
    }
    var e = fixture("api-error");
    assertEquals(
        e,
        projection(
            new ApiErrorHandler.ErrorResponse(
                "not_found",
                "Entity not found",
                Map.of("resource", "project", "id", e.get("details").get("id").asText()))));
  }

  @Test
  void sharedEventHasValidIdentifiersAndTimestamp() throws Exception {
    var e = fixture("project-event");
    assertNotNull(id(e, "eventId"));
    assertNotNull(id(e, "projectId"));
    assertNotNull(Instant.parse(e.get("occurredAt").asText()));
    assertEquals(1, e.get("schemaVersion").asInt());
    assertTrue(Long.parseLong(e.get("seq").asText()) > 0);
  }
}
