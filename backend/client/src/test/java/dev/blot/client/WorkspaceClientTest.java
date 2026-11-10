package dev.blot.client;

import static org.junit.jupiter.api.Assertions.*;

import com.sun.net.httpserver.HttpServer;
import dev.blot.core.v3.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.atomic.*;
import org.junit.jupiter.api.Test;

class WorkspaceClientTest {
  @Test
  void rejectsCredentialBearingOrInsecureRemoteAddresses() {
    for (String address :
        List.of(
            "http://example.org",
            "https://user:secret@example.org",
            "https://example.org/v3",
            "https://example.org?token=secret"))
      assertThrows(
          IllegalArgumentException.class,
          () -> new WorkspaceClient(URI.create(address), "session"));
  }

  @Test
  void reconcilesACommittedCommandAfterServerErrorAndRetainsItsExactEnvelope() throws Exception {
    UUID owner = UUID.randomUUID(), workspace = UUID.randomUUID(), commandId = UUID.randomUUID();
    var codec = new WorkspaceJson();
    var body = new AtomicReference<String>();
    var posts = new AtomicInteger();
    var receipt = new AtomicReference<String>();
    var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext(
        "/",
        exchange -> {
          assertEquals(
              "Bearer private-session", exchange.getRequestHeaders().getFirst("Authorization"));
          int status = 200;
          String result;
          String path = exchange.getRequestURI().getPath();
          if (path.equals("/v3/compatibility"))
            result =
                codec.encode(
                    Map.of(
                        "schemaVersions", List.of(3), "ownerId", owner, "workspaceId", workspace));
          else if (path.equals("/v3/snapshot"))
            result = "{\"schemaVersion\":3,\"sequence\":0,\"records\":{},\"nextCursor\":null}";
          else if (path.equals("/v3/commands")) {
            String request =
                new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            if (body.get() == null) body.set(request);
            else assertEquals(body.get(), request);
            posts.incrementAndGet();
            receipt.compareAndSet(
                null,
                codec.encode(
                    Map.of(
                        "schemaVersion",
                        3,
                        "commandId",
                        commandId,
                        "operationId",
                        UUID.randomUUID(),
                        "state",
                        "ACCEPTED")));
            status = 503;
            result = "{\"code\":\"unavailable\",\"message\":\"Try later\"}";
          } else result = receipt.get();
          byte[] bytes = result.getBytes(StandardCharsets.UTF_8);
          exchange.getResponseHeaders().add("Content-Type", "application/json");
          exchange.sendResponseHeaders(status, bytes.length);
          try (var output = exchange.getResponseBody()) {
            output.write(bytes);
          }
        });
    server.start();
    try {
      var client =
          new WorkspaceClient(
              URI.create("http://127.0.0.1:" + server.getAddress().getPort()), "private-session");
      client.connect();
      var metadata =
          new RecordMetadata(UUID.randomUUID(), owner, workspace, 1, Instant.now(), Instant.now());
      var chat =
          new Conversation(
              metadata, UUID.randomUUID(), "Chat", false, false, false, ConversationKind.DIRECT);
      var accepted = client.send(chat, "Hello", commandId);
      assertEquals("ACCEPTED", accepted.state());
      assertEquals(accepted, client.send(chat, "Hello", commandId));
      assertEquals(2, posts.get());
      assertThrows(IllegalArgumentException.class, () -> client.send(chat, "Different", commandId));
    } finally {
      server.stop(0);
    }
  }

  @Test
  void neverFollowsAnAuthenticatedRedirect() throws Exception {
    var leaked = new AtomicBoolean();
    var target = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    target.createContext(
        "/",
        exchange -> {
          leaked.set(true);
          exchange.sendResponseHeaders(200, -1);
          exchange.close();
        });
    var source = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    source.createContext(
        "/",
        exchange -> {
          exchange
              .getResponseHeaders()
              .add("Location", "http://127.0.0.1:" + target.getAddress().getPort());
          exchange.sendResponseHeaders(302, -1);
          exchange.close();
        });
    target.start();
    source.start();
    try {
      var client =
          new WorkspaceClient(
              URI.create("http://127.0.0.1:" + source.getAddress().getPort()), "private-session");
      var failure = assertThrows(WorkspaceClient.Failure.class, client::connect);
      assertEquals(302, failure.status());
      assertFalse(leaked.get());
    } finally {
      source.stop(0);
      target.stop(0);
    }
  }
}
