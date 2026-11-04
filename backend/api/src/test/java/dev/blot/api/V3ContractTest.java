package dev.blot.api;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.core.*;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.module.SimpleModule;
import java.io.IOException;
import java.nio.file.*;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class V3ContractTest {
  private ObjectMapper mapper() {
    var module = new SimpleModule();
    module.addSerializer(
        Instant.class,
        new JsonSerializer<Instant>() {
          @Override
          public void serialize(Instant value, JsonGenerator g, SerializerProvider p)
              throws IOException {
            g.writeString(value.toString());
          }
        });
    module.addDeserializer(
        Instant.class,
        new JsonDeserializer<Instant>() {
          @Override
          public Instant deserialize(JsonParser p, DeserializationContext c) throws IOException {
            return Instant.parse(p.getValueAsString());
          }
        });
    return new ObjectMapper().registerModule(module);
  }

  @Test
  void everyPublicRecordRoundTrips() throws Exception {
    var mapper = mapper();
    var dir = Path.of(System.getProperty("blot.fixtures")).getParent().resolve("v3");
    for (String name :
        java.util.List.of(
            "Project",
            "Account",
            "Device",
            "TrustedPair",
            "Workspace",
            "AgentProfile",
            "AgentConfigurationRevision",
            "Conversation",
            "Message",
            "Message-rich",
            "Task",
            "TaskAttempt",
            "Assignment",
            "AgentSession",
            "AgentMessage",
            "PreparedAction",
            "ApprovalGrant",
            "ToolInvocation",
            "Artifact",
            "MemoryEntry",
            "ContextSummary",
            "Connection",
            "McpConnection",
            "Automation",
            "AutomationRun",
            "BudgetLedger",
            "SyncCursor",
            "ConversationParticipant",
            "MessageReaction",
            "ConversationReadPosition",
            "Skill",
            "SkillRevision",
            "RecordChange",
            "RecordTombstone",
            "ReplicationCheckpoint",
            "ConflictingRevision",
            "ExecutionLease")) {
      var type = Class.forName("dev.blot.core.v3." + name.split("-")[0]);
      var original = mapper.readTree(dir.resolve(name + ".json").toFile());
      var value = mapper.treeToValue(original, type);
      assertEquals(original, mapper.readTree(mapper.writeValueAsBytes(value)), name);
    }
  }

  @Test
  void everyEnumMatchesTheSharedStateCatalog() throws Exception {
    var mapper = mapper();
    var states =
        mapper.readTree(
            Path.of(System.getProperty("blot.fixtures"))
                .getParent()
                .resolve("v3/states.json")
                .toFile());
    for (var entry : states.properties()) {
      var type = Class.forName("dev.blot.core.v3." + entry.getKey());
      assertEquals(entry.getValue(), mapper.valueToTree(type.getEnumConstants()), entry.getKey());
    }
  }

  @Test
  void countersRejectInvalidValues() {
    assertThrows(
        IllegalArgumentException.class,
        () ->
            new dev.blot.core.v3.ExecutionContext(
                java.util.UUID.randomUUID(),
                java.util.UUID.randomUUID(),
                java.util.UUID.randomUUID(),
                -1,
                null));
  }
}
