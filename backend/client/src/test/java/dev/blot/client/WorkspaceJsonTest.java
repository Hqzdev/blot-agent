package dev.blot.client;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.blot.core.v3.Message;
import dev.blot.core.v3.Task;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

public final class WorkspaceJsonTest {
  private final WorkspaceJson records = new WorkspaceJson();

  private String fixture(String name) throws Exception {
    try (var stream = getClass().getResourceAsStream("/" + name + ".json")) {
      assertNotNull(stream, name);
      return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
    }
  }

  @Test
  public void preservesRichMessagesAndTaskExecutionFields() throws Exception {
    var json = new ObjectMapper();
    for (String name :
        new String[] {
          "Account",
          "Device",
          "TrustedPair",
          "Workspace",
          "Project",
          "AgentProfile",
          "AgentConfigurationRevision",
          "Conversation",
          "Message",
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
          "ExecutionLease",
          "ModelStep",
          "Message-rich"
        }) {
      Class<?> type = Class.forName("dev.blot.core.v3." + name.split("-")[0]);
      String source = fixture(name);
      assertEquals(
          json.readTree(source), json.readTree(records.encode(records.decode(source, type))), name);
    }
  }

  @Test
  public void matchesSharedStateCatalog() throws Exception {
    var mapper = new ObjectMapper();
    var states = mapper.readTree(fixture("states"));
    var entries = states.fields();
    while (entries.hasNext()) {
      var entry = entries.next();
      var type = Class.forName("dev.blot.core.v3." + entry.getKey());
      assertEquals(entry.getValue(), mapper.valueToTree(type.getEnumConstants()), entry.getKey());
    }
  }

  @Test
  public void readsLegacyMessagesWithMissingOptionalFields() throws Exception {
    var tree = new ObjectMapper().readTree(fixture("Message-rich"));
    var old = (com.fasterxml.jackson.databind.node.ObjectNode) tree;
    for (String key :
        new String[] {
          "authorAgentId", "replyToMessageId", "mentions", "position", "executorDeviceId"
        }) old.remove(key);
    Message message = records.decode(old.toString(), Message.class);
    assertNull(message.mentions());
    assertNull(message.position());
    assertEquals(tree.get("content").asText(), message.content());
  }

  @Test
  public void rejectsInvalidRecordCounters() throws Exception {
    var old =
        (com.fasterxml.jackson.databind.node.ObjectNode)
            new ObjectMapper().readTree(fixture("Task"));
    old.put("budgetTokenLimit", -1);
    assertThrows(java.io.IOException.class, () -> records.decode(old.toString(), Task.class));
  }
}
