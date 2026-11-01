package dev.blot.api;

import com.fasterxml.jackson.databind.*;
import dev.blot.api.workspace.security.TlsConfiguration;
import dev.blot.application.ports.*;
import dev.blot.application.ports.EmailSender;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.planning.CoverageData;
import dev.blot.core.workspace.planning.PlanStepData;
import dev.blot.core.workspace.planning.RequirementData;
import dev.blot.core.workspace.projects.RunData;
import dev.blot.infrastructure.workspace.security.TlsIdentity;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class HttpApiTest {
  @TempDir Path directory;

  @Configuration
  static class Fixtures {
    static final Map<String, String> codes = new ConcurrentHashMap<>();

    @Bean
    @Primary
    EmailSender captureMail() {
      return (email, code, purpose) -> codes.put(email + ":" + purpose, code);
    }

    @Bean
    @Primary
    SecretStore localSecrets() {
      return new SecretStore() {
        final Map<String, String> values = new ConcurrentHashMap<>();

        public Optional<String> get(String k) {
          return Optional.ofNullable(values.get(k));
        }

        public void put(String k, String v) {
          values.put(k, v);
        }

        public void remove(String k) {
          values.remove(k);
        }
      };
    }
  }

  @Test
  void authenticatedCommandsRetryIsolationAndLegacyClosure() throws Exception {
    var app = new SpringApplication(BlotServer.class, Fixtures.class);
    app.setDefaultProperties(
        Map.of(
            "server.port",
            "0",
            "blot.database",
            directory.resolve("database/blot.db").toString(),
            "blot.data-directory",
            directory.resolve("state").toString(),
            "blot.worker.enabled",
            "false",
            "blot.automations.enabled",
            "false"));
    try (var context =
        app.run(
            "--server.port=0",
            "--blot.database=" + directory.resolve("database/blot.db"),
            "--blot.data-directory=" + directory.resolve("state"),
            "--blot.worker.enabled=false",
            "--blot.automations.enabled=false")) {
      int port = ((WebServerApplicationContext) context).getWebServer().getPort();
      String base = "http://127.0.0.1:" + port;
      var http = HttpClient.newHttpClient();
      var json = new ObjectMapper();
      String token = register(http, base, "first@example.com");
      var unauthorized = send(http, base, "/v2/records/CONVERSATION", "GET", null, null);
      assertEquals(401, unauthorized.statusCode());
      assertEquals(401, send(http, base, "/v2/statistics", "GET", null, null).statusCode());
      var statistics = send(http, base, "/v2/statistics", "GET", null, token);
      assertEquals(200, statistics.statusCode());
      assertEquals(0, json.readTree(statistics.body()).path("knownInputTokens").asLong());
      assertTrue(json.readTree(statistics.body()).path("costMinorUnits").isNull());
      UUID command = UUID.randomUUID();
      String body =
          json.writeValueAsString(
              Map.of(
                  "schemaVersion",
                  2,
                  "commandId",
                  command,
                  "type",
                  "conversation.create",
                  "payload",
                  Map.of("title", "Test chat")));
      var created = send(http, base, "/v2/commands", "POST", body, token);
      assertEquals(202, created.statusCode(), created.body());
      String id = json.readTree(created.body()).path("result").path("id").asText();
      assertFalse(id.isBlank());
      var retry = send(http, base, "/v2/commands", "POST", body, token);
      assertEquals(202, retry.statusCode());
      assertEquals(
          json.readTree(created.body()).path("operationId"),
          json.readTree(retry.body()).path("operationId"));
      var read = send(http, base, "/v2/records/CONVERSATION/" + id, "GET", null, token);
      assertEquals(200, read.statusCode());
      var project = desktopCommand(http, base, token, "project.create", null, null,
          Map.of("name", "Research"), UUID.randomUUID()).path("result");
      UUID projectId = UUID.fromString(project.path("id").asText());
      assertEquals("", project.path("data").path("repositoryPath").asText());
      desktopCommand(http, base, token, "memory.save", projectId, null,
          Map.of("data", Map.of("scope", "project", "status", "active", "content", "Project brief")),
          UUID.randomUUID());
      var projectChat = desktopCommand(http, base, token, "conversation.create", projectId, null,
          Map.of("title", "First question"), UUID.randomUUID()).path("result");
      desktopCommand(http, base, token, "conversation.send_message", null, null,
          Map.of("conversationId", projectChat.path("id").asText(), "content", "Hello"), UUID.randomUUID());
      assertEquals(projectId.toString(), projectChat.path("projectId").asText());
      desktopCommand(http, base, token, "conversation.send_message", null, null,
          Map.of("conversationId", id, "content", "Hello without a project"), UUID.randomUUID());
      String second = register(http, base, "second@example.com");
      assertEquals(
          404,
          send(http, base, "/v2/records/CONVERSATION/" + id, "GET", null, second).statusCode());
      var old =
          send(
              http,
              base,
              "/projects",
              "POST",
              "{\"name\":\"Unprotected\",\"repositoryPath\":\"/tmp\"}",
              null);
      assertEquals(404, old.statusCode());
      assertEquals(200, send(http, base, "/ready", "GET", null, null).statusCode());
      Path fixtures = Path.of(System.getProperty("blot.httpFixtures"));
      Files.createDirectories(fixtures);
      Files.writeString(fixtures.resolve("workspace-conversation.json"), read.body());
      var snapshot = send(http, base, "/v2/snapshot", "GET", null, token);
      assertEquals(200, snapshot.statusCode());
      assertFalse(snapshot.body().contains("passwordHash"));
      assertFalse(snapshot.body().contains("codeHash"));
      var logout = send(http, base, "/v2/auth/logout", "POST", "{}", token);
      assertEquals(200, logout.statusCode());
      assertEquals(401, send(http, base, "/v2/auth/me", "GET", null, token).statusCode());
    }
  }

  @Test
  void desktopWorkspaceUsesCommandsForRunsSkillsAndSchedules() throws Exception {
    Path repository = Files.createDirectory(directory.resolve("repository"));
    fixtureGit(repository, "init", "-b", "main");
    fixtureGit(repository, "commit", "--allow-empty", "-m", "Base");
    var app = new SpringApplication(BlotServer.class, Fixtures.class);
    try (var context =
        app.run(
            "--server.port=0",
            "--blot.database=" + directory.resolve("desktop.db"),
            "--blot.data-directory=" + directory.resolve("desktop-state"),
            "--blot.worker.enabled=false",
            "--blot.automations.enabled=true")) {
      String base =
          "http://127.0.0.1:" + ((WebServerApplicationContext) context).getWebServer().getPort();
      var http = HttpClient.newHttpClient();
      var json = new ObjectMapper();
      String token = register(http, base, "desktop@example.com");
      var project =
          desktopCommand(
                  http,
                  base,
                  token,
                  "project.create",
                  null,
                  null,
                  Map.of("name", "Desktop", "repositoryPath", repository.toString()),
                  UUID.randomUUID())
              .path("result");
      UUID projectId = UUID.fromString(project.path("id").asText());
      var run =
          desktopCommand(
                  http,
                  base,
                  token,
                  "run.create",
                  projectId,
                  null,
                  Map.of("goal", "Implement the feature", "tokenBudget", 100000),
                  UUID.randomUUID())
              .path("result");
      UUID runId = UUID.fromString(run.path("id").asText());
      UUID owner = UUID.fromString(run.path("ownerId").asText());
      var store = context.getBean(WorkspaceStore.class);
      var runs = context.getBean(RunService.class);
      store.transact(
          tx ->
              runs.propose(
                  tx,
                  dev.blot.application.workspace.Records.require(
                      tx,
                      dev.blot.core.workspace.EntityKind.RUN,
                      owner,
                      runId,
                      RunData.class),
                  List.of(
                      new PlanStepData(
                          "build",
                          "Implement",
                          List.of("Result reviewed"),
                          List.of(),
                          "BACKEND",
                          List.of("."))),
                  List.of(
                      new RequirementData("r1", "Implement the feature")),
                  List.of(new CoverageData("r1", List.of("build")))));
      for (String type : List.of("run.plan.approve", "run.pause", "run.resume", "run.stop")) {
        var current =
            json.readTree(send(http, base, "/v2/records/RUN/" + runId, "GET", null, token).body());
        desktopCommand(
            http,
            base,
            token,
            type,
            projectId,
            current.path("version").asLong(),
            Map.of("id", runId),
            UUID.randomUUID());
      }
      var skill =
          desktopCommand(
                  http,
                  base,
                  token,
                  "skill.save",
                  projectId,
                  null,
                  Map.of(
                      "data",
                      Map.of(
                          "name",
                          "Readable code",
                          "instruction",
                          "Use clear function names",
                          "roles",
                          List.of("BACKEND"),
                          "enabled",
                          true)),
                  UUID.randomUUID())
              .path("result");
      desktopCommand(
          http,
          base,
          token,
          "skill.save",
          projectId,
          skill.path("version").asLong(),
          Map.of(
              "id",
              skill.path("id").asText(),
              "data",
              Map.of(
                  "name",
                  "Readable code",
                  "instruction",
                  "Use clear function names",
                  "roles",
                  List.of("BACKEND"),
                  "enabled",
                  false)),
          UUID.randomUUID());
      var automation =
          desktopCommand(
                  http,
                  base,
                  token,
                  "automation.save",
                  projectId,
                  null,
                  Map.of(
                      "data",
                      Map.of(
                          "name",
                          "Daily review",
                          "goal",
                          "Review the project",
                          "timezone",
                          "Asia/Yekaterinburg",
                          "localTime",
                          "09:00",
                          "weekdays",
                          List.of(1, 2, 3, 4, 5),
                          "enabled",
                          false,
                          "tokenBudget",
                          100000)),
                  UUID.randomUUID())
              .path("result");
      UUID manualId = UUID.randomUUID();
      var first =
          desktopCommand(
              http,
              base,
              token,
              "automation.run_now",
              projectId,
              automation.path("version").asLong(),
              Map.of("id", automation.path("id").asText()),
              manualId);
      var repeated =
          desktopCommand(
              http,
              base,
              token,
              "automation.run_now",
              projectId,
              automation.path("version").asLong(),
              Map.of("id", automation.path("id").asText()),
              manualId);
      assertEquals(first.path("operationId"), repeated.path("operationId"));
      var history =
          json.readTree(
              send(
                      http,
                      base,
                      "/v2/records/CHECKPOINT?parentId=" + automation.path("id").asText(),
                      "GET",
                      null,
                      token)
                  .body());
      assertEquals(1, history.size());
      assertEquals(
          first.path("operationId").asText(), history.get(0).path("data").path("runId").asText());
      var budgets =
          json.readTree(
              send(
                      http,
                      base,
                      "/v2/records/BUDGET?parentId=" + first.path("operationId").asText(),
                      "GET",
                      null,
                      token)
                  .body());
      assertEquals(100000, budgets.get(0).path("data").path("limit").asLong());
      String other = register(http, base, "desktop-other@example.com");
      assertEquals(
          404,
          send(
                  http,
                  base,
                  "/v2/records/AUTOMATION/" + automation.path("id").asText(),
                  "GET",
                  null,
                  other)
              .statusCode());
      var snapshot = send(http, base, "/v2/snapshot", "GET", null, token);
      assertEquals(200, snapshot.statusCode());
      Path fixtures = Path.of(System.getProperty("blot.httpFixtures"));
      Files.createDirectories(fixtures);
      Files.writeString(fixtures.resolve("workspace-desktop.json"), snapshot.body());
    }
  }

  private JsonNode desktopCommand(
      HttpClient http,
      String base,
      String token,
      String type,
      UUID project,
      Long version,
      Map<String, Object> payload,
      UUID commandId)
      throws Exception {
    var body = new LinkedHashMap<String, Object>();
    body.put("schemaVersion", 2);
    body.put("commandId", commandId);
    body.put("type", type);
    body.put("projectId", project);
    body.put("expectedVersion", version);
    body.put("payload", payload);
    var json = new ObjectMapper();
    var response = send(http, base, "/v2/commands", "POST", json.writeValueAsString(body), token);
    assertEquals(202, response.statusCode(), response.body());
    return json.readTree(response.body());
  }

  private void fixtureGit(Path repository, String... arguments) throws Exception {
    var command =
        new ArrayList<>(
            List.of(
                "/usr/bin/git",
                "-C",
                repository.toString(),
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.com",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.hooksPath=/dev/null"));
    command.addAll(List.of(arguments));
    var builder = new ProcessBuilder(command).redirectErrorStream(true);
    builder.environment().put("GIT_CONFIG_GLOBAL", "/dev/null");
    builder.environment().put("GIT_CONFIG_NOSYSTEM", "1");
    var process = builder.start();
    String output =
        new String(
            process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    assertEquals(0, process.waitFor(), output);
  }

  @Test
  void tlsIdentityAndBleConnectorKeepLocalAccountBoundary() throws Exception {
    var app = new SpringApplication(BlotServer.class, Fixtures.class);
    try (var context =
        app.run(
            "--server.port=0",
            "--blot.tls.enabled=true",
            "--blot.database=" + directory.resolve("tls.db"),
            "--blot.data-directory=" + directory.resolve("tls-state"),
            "--blot.worker.enabled=false",
            "--blot.automations.enabled=false")) {
      var identity = context.getBean(TlsIdentity.class);
      var trust = java.security.KeyStore.getInstance("PKCS12");
      try (var input = Files.newInputStream(identity.keystore())) {
        trust.load(input, identity.password().toCharArray());
      }
      var manager =
          javax.net.ssl.TrustManagerFactory.getInstance(
              javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm());
      manager.init(trust);
      var ssl = javax.net.ssl.SSLContext.getInstance("TLS");
      ssl.init(null, manager.getTrustManagers(), null);
      var http = HttpClient.newBuilder().sslContext(ssl).build();
      int port = ((WebServerApplicationContext) context).getWebServer().getPort();
      String token = register(http, "https://127.0.0.1:" + port, "tls@example.com");
      int ble = context.getBean(TlsConfiguration.BleConnector.class).port();
      assertTrue(ble > 0);
      assertNotEquals(port, ble);
      var login =
          send(
              http,
              "https://127.0.0.1:" + ble,
              "/v2/auth/login",
              "POST",
              "{\"email\":\"tls@example.com\",\"password\":\"correct horse battery\",\"remember\":true}",
              null);
      assertEquals(403, login.statusCode());
      assertEquals(
          401,
          send(http, "https://127.0.0.1:" + ble, "/v2/auth/me", "GET", null, token).statusCode());
    }
  }

  private String register(HttpClient http, String base, String email) throws Exception {
    var json = new ObjectMapper();
    String credentials =
        json.writeValueAsString(
            Map.of("email", email, "password", "correct horse battery", "remember", true));
    var created = send(http, base, "/v2/auth/register", "POST", credentials, null);
    assertEquals(200, created.statusCode(), created.body());
    var verified =
        send(
            http,
            base,
            "/v2/auth/verify",
            "POST",
            json.writeValueAsString(
                Map.of("email", email, "code", Fixtures.codes.get(email + ":verify"))),
            null);
    assertEquals(200, verified.statusCode(), verified.body());
    var login = send(http, base, "/v2/auth/login", "POST", credentials, null);
    assertEquals(200, login.statusCode(), login.body());
    return json.readTree(login.body()).path("session").path("token").asText();
  }

  private HttpResponse<String> send(
      HttpClient http, String base, String path, String method, String body, String token)
      throws Exception {
    var b =
        HttpRequest.newBuilder(URI.create(base + path)).header("Content-Type", "application/json");
    if (token != null) b.header("Authorization", "Bearer " + token);
    b.method(
        method,
        body == null
            ? HttpRequest.BodyPublishers.noBody()
            : HttpRequest.BodyPublishers.ofString(body));
    return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
  }
}
