package dev.blot.api;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.blot.application.ports.*;
import dev.blot.application.workspace.v3.*;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.infrastructure.workspace.JacksonCodec;
import dev.blot.infrastructure.workspace.database.SqliteV3Store;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;

class V3HttpTest {
  @TempDir Path directory;
  private final ObjectMapper json = new ObjectMapper();
  private final HttpClient http = HttpClient.newHttpClient();

  @Configuration
  @Profile("v3-http-test")
  static class ModelFixture {
    static final AtomicInteger calls = new AtomicInteger();

    @Bean
    @Primary
    ProviderGateway v3TestProvider() {
      return new ProviderGateway() {
        public Reply generate(
            Request request,
            java.util.function.Consumer<String> text,
            java.util.function.BooleanSupplier cancelled) {
          calls.incrementAndGet();
          return new Reply(
              "Confirmed: " + request.messages().getLast().content(), List.of(), 2L, 3L);
        }

        public List<String> models(UUID owner) {
          return List.of("fixture-model");
        }

        public long countTokens(UUID owner, String model, String text) {
          return text.length();
        }
      };
    }
  }

  @Test
  void realHttpPersistsCommandsIsolatesOwnersAndDeliversAnActualModelReply() throws Exception {
    var app =
        new SpringApplication(BlotServer.class, HttpApiTest.Fixtures.class, ModelFixture.class);
    try (var context =
        app.run(
            "--spring.profiles.active=v3-http-test",
            "--server.port=0",
            "--blot.database=" + directory.resolve("v2.db"),
            "--blot.data-directory=" + directory.resolve("state"),
            "--blot.worker.enabled=false",
            "--blot.automations.enabled=false")) {
      String base =
          "http://127.0.0.1:" + ((WebServerApplicationContext) context).getWebServer().getPort();
      String token = register(base, "v3@example.org"),
          other = register(base, "other-v3@example.org");
      assertEquals(401, send(base, "/v3/snapshot", "GET", null, null).statusCode());
      var compatibility = tree(send(base, "/v3/compatibility", "GET", null, token), 200);
      UUID workspace = UUID.fromString(compatibility.path("workspaceId").asText());
      var profile =
          json.readTree(
              Path.of(System.getProperty("blot.fixtures"))
                  .getParent()
                  .resolve("v3/AgentProfile.json")
                  .toFile());
      ((ObjectNode) profile).put("modelId", "fixture-model");
      UUID agentId = UUID.fromString(profile.path("metadata").path("id").asText());
      var save = command("agent.save", Map.of("profile", profile), null);
      assertEquals(202, send(base, "/v3/commands", "POST", save, token).statusCode());
      var saved = tree(send(base, "/v3/snapshot", "GET", null, token), 200);
      var agent = saved.path("records").path("AgentProfile").get(0);
      assertEquals(workspace.toString(), agent.path("metadata").path("workspaceId").asText());
      assertNotEquals(
          profile.path("metadata").path("ownerId"), agent.path("metadata").path("ownerId"));
      assertTrue(
          tree(send(base, "/v3/snapshot", "GET", null, other), 200).path("records").isEmpty());
      var create =
          command("conversation.create", Map.of("title", "Real chat", "agentId", agentId), null);
      var first = send(base, "/v3/commands", "POST", create, token);
      assertEquals(202, first.statusCode());
      assertEquals(first.body(), send(base, "/v3/commands", "POST", create, token).body());
      var changed = json.readTree(create);
      ((ObjectNode) changed.path("payload")).put("title", "Changed");
      assertEquals(409, send(base, "/v3/commands", "POST", changed.toString(), token).statusCode());
      var snapshot = tree(send(base, "/v3/snapshot", "GET", null, token), 200);
      UUID conversation =
          UUID.fromString(
              snapshot
                  .path("records")
                  .path("Conversation")
                  .get(0)
                  .path("metadata")
                  .path("id")
                  .asText());
      var message =
          command(
              "conversation.send_message",
              Map.of("conversationId", conversation, "content", "Hello", "artifactIds", List.of()),
              1L);
      int calls = ModelFixture.calls.get();
      assertEquals(202, send(base, "/v3/commands", "POST", message, token).statusCode());
      assertEquals(202, send(base, "/v3/commands", "POST", message, token).statusCode());
      boolean completed = false;
      long deadline = System.nanoTime() + Duration.ofSeconds(10).toNanos();
      while (System.nanoTime() < deadline && !completed) {
        var response = tree(send(base, "/v3/snapshot", "GET", null, token), 200);
        for (var record : response.path("records").path("Message")) {
          if (record.path("delivery").asText().equals("COMPLETED")) {
            assertEquals("Confirmed: Hello", record.path("content").asText());
            completed = true;
          }
        }
        if (!completed) Thread.sleep(50);
      }
      assertTrue(completed);
      assertEquals(calls + 1, ModelFixture.calls.get());
      var client = new dev.blot.client.WorkspaceClient(URI.create(base), token);
      var clientState = client.connect();
      assertEquals(1, clientState.agents().size());
      assertEquals(2, clientState.messages().size());
      UUID nextCommand = UUID.randomUUID();
      var accepted = client.send(clientState.conversations().getFirst(), "Second", nextCommand);
      assertEquals(
          accepted, client.send(clientState.conversations().getFirst(), "Second", nextCommand));
      assertEquals("ACCEPTED", client.receipt(nextCommand).state());
      assertEquals(
          404,
          send(
                  base,
                  "/v3/commands",
                  "POST",
                  command(
                      "conversation.update",
                      Map.of("conversationId", conversation, "title", "Stolen"),
                      1L),
                  other)
              .statusCode());
      assertEquals(
          409,
          send(
                  base,
                  "/v3/commands",
                  "POST",
                  command(
                      "conversation.update",
                      Map.of("conversationId", conversation, "title", "Stale"),
                      0L),
                  token)
              .statusCode());
      assertEquals(
          501,
          send(base, "/v3/commands", "POST", command("task.create", Map.of(), null), token)
              .statusCode());
      var store = context.getBean(V3Store.class);
      var owner = UUID.fromString(agent.path("metadata").path("ownerId").asText());
      assertTrue(
          store.transact(owner, tx -> tx.events(0, 100)).stream()
              .allMatch(e -> e.schemaVersion() == 3));
      assertEquals(
          202,
          send(
                  base,
                  "/v3/commands",
                  "POST",
                  command("conversation.delete", Map.of("conversationId", conversation), 1L),
                  token)
              .statusCode());
      assertFalse(
          tree(send(base, "/v3/snapshot", "GET", null, token), 200).path("records").has("Message"));
    }
  }

  @Test
  void snapshotPaginationRetainsOldRevisionsAndReceiptsSurviveReopen() {
    var codec = new JacksonCodec();
    var database = directory.resolve("v3.db");
    var store = new SqliteV3Store(database, codec);
    var workspace = new V3Workspace(store, codec, Clock.systemUTC());
    UUID owner = UUID.randomUUID();
    var actor = new Actor(owner, UUID.randomUUID(), null, true);
    for (String title : List.of("A", "B", "C")) {
      var payload = new HashMap<String, Object>();
      payload.put("title", title);
      payload.put("agentId", null);
      workspace.execute(
          actor,
          new V3Workspace.Command(
              3,
              UUID.randomUUID(),
              null,
              "conversation.create",
              null,
              Instant.now().plusSeconds(60),
              payload));
    }
    var first = workspace.snapshot(owner, null, 1);
    assertNotNull(first.nextCursor());
    var second = workspace.snapshot(owner, first.nextCursor(), 1);
    var row = second.records().get("Conversation").getFirst();
    var metadata = (Map<?, ?>) row.get("metadata");
    UUID id = UUID.fromString(metadata.get("id").toString());
    var change =
        new V3Workspace.Command(
            3,
            UUID.randomUUID(),
            null,
            "conversation.update",
            1L,
            Instant.now().plusSeconds(60),
            Map.of("conversationId", id.toString(), "title", "New title"));
    var receipt = workspace.execute(actor, change);
    assertEquals(
        row,
        workspace.snapshot(owner, first.nextCursor(), 1).records().get("Conversation").getFirst());
    assertEquals(
        receipt,
        new V3Workspace(new SqliteV3Store(database, codec), codec, Clock.systemUTC())
            .execute(actor, change));
    var stranger = UUID.randomUUID();
    assertThrows(
        dev.blot.application.workspace.WorkspaceFailure.class,
        () -> workspace.snapshot(stranger, first.nextCursor(), 1));
  }

  private String register(String base, String email) throws Exception {
    String credentials =
        json.writeValueAsString(
            Map.of(
                "email", email, "password", "LongPassword123!", "name", "V3", "remember", false));
    assertEquals(200, send(base, "/v2/auth/register", "POST", credentials, null).statusCode());
    String code = HttpApiTest.Fixtures.codes.get(email + ":verify");
    assertEquals(
        200,
        send(
                base,
                "/v2/auth/verify",
                "POST",
                json.writeValueAsString(Map.of("email", email, "code", code)),
                null)
            .statusCode());
    return tree(send(base, "/v2/auth/login", "POST", credentials, null), 200)
        .path("session")
        .path("token")
        .asText();
  }

  private String command(String type, Map<String, ?> payload, Long version) throws Exception {
    var value = new LinkedHashMap<String, Object>();
    value.put("schemaVersion", 3);
    value.put("commandId", UUID.randomUUID());
    value.put("workspaceId", null);
    value.put("type", type);
    value.put("expectedVersion", version);
    value.put("expiresAt", Instant.now().plusSeconds(60).toString());
    value.put("payload", payload);
    return json.writeValueAsString(value);
  }

  private HttpResponse<String> send(
      String base, String path, String method, String body, String token) throws Exception {
    var request =
        HttpRequest.newBuilder(URI.create(base + path))
            .timeout(Duration.ofSeconds(15))
            .header("Content-Type", "application/json");
    if (token != null) request.header("Authorization", "Bearer " + token);
    return http.send(
        request
            .method(
                method,
                body == null
                    ? HttpRequest.BodyPublishers.noBody()
                    : HttpRequest.BodyPublishers.ofString(body))
            .build(),
        HttpResponse.BodyHandlers.ofString());
  }

  private JsonNode tree(HttpResponse<String> response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.body());
    return json.readTree(response.body());
  }
}
