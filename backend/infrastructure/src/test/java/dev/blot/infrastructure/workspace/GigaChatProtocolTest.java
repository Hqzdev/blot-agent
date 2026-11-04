package dev.blot.infrastructure.workspace;

import static org.junit.jupiter.api.Assertions.*;

import com.sun.net.httpserver.*;
import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.SecretStore;
import dev.blot.infrastructure.workspace.provider.GigaChatGateway;
import dev.blot.infrastructure.workspace.security.TlsIdentity;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import javax.net.ssl.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class GigaChatProtocolTest {
  @TempDir Path directory;

  @Test
  void tlsOAuthCacheAndFragmentedFunctionArguments() throws Exception {
    SecretStore secrets =
        new SecretStore() {
          private final Map<String, String> values = new ConcurrentHashMap<>();

          public Optional<String> get(String key) {
            return Optional.ofNullable(values.get(key));
          }

          public void put(String key, String value) {
            values.put(key, value);
          }

          public void remove(String key) {
            values.remove(key);
          }
        };
    var identity = new TlsIdentity(directory, secrets);
    var keys = KeyStore.getInstance("PKCS12");
    try (var input = Files.newInputStream(identity.keystore())) {
      keys.load(input, identity.password().toCharArray());
    }
    var km = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    km.init(keys, identity.password().toCharArray());
    var tm = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
    tm.init(keys);
    var tls = SSLContext.getInstance("TLS");
    tls.init(km.getKeyManagers(), tm.getTrustManagers(), null);
    var server = HttpsServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.setHttpsConfigurator(new HttpsConfigurator(tls));
    var authorizationCalls = new AtomicInteger();
    server.createContext(
        "/oauth",
        exchange -> {
          authorizationCalls.incrementAndGet();
          respond(
              exchange,
              "application/json",
              "{\"access_token\":\"test-access\",\"expires_at\":"
                  + (System.currentTimeMillis() + 3600000)
                  + "}");
        });
    server.createContext(
        "/v1/models",
        exchange -> respond(exchange, "application/json", "{\"data\":[{\"id\":\"test-model\"}]}"));
    server.createContext(
        "/v1/chat/completions",
        exchange ->
            respond(
                exchange,
                "text/event-stream",
                """
    data: {"choices":[{"delta":{"function_call":{"name":"project_read_file","arguments":"{\\"path\\":"},"functions_state_id":"state-1"}}]}

    data: {"choices":[{"delta":{"function_call":{"arguments":"\\"source.txt\\"}"}},"finish_reason":"function_call"}],"usage":{"prompt_tokens":12,"completion_tokens":4}}

    data: [DONE]

    """));
    server.start();
    try {
      UUID owner = UUID.randomUUID();
      secrets.put("provider." + owner, "test-only-key");
      var uri = URI.create("https://127.0.0.1:" + server.getAddress().getPort() + "/");
      var gateway =
          new GigaChatGateway(
              HttpClient.newBuilder().sslContext(tls).build(),
              new JacksonCodec(),
              secrets,
              uri.resolve("v1/"),
              uri.resolve("oauth"),
              Clock.systemUTC());
      try (var workers = Executors.newVirtualThreadPerTaskExecutor()) {
        var first = workers.submit(() -> gateway.models(owner));
        var second = workers.submit(() -> gateway.models(owner));
        assertEquals(List.of("test-model"), first.get(5, TimeUnit.SECONDS));
        assertEquals(List.of("test-model"), second.get(5, TimeUnit.SECONDS));
      }
      assertEquals(1, authorizationCalls.get());
      secrets.put("provider." + owner, "new-test-key");
      assertEquals(List.of("test-model"), gateway.models(owner));
      assertEquals(2, authorizationCalls.get());
      var reply =
          gateway.generate(
              new ProviderGateway.Request(
                  owner,
                  "test-model",
                  List.of(new ProviderGateway.Message("user", "Read", null, null)),
                  List.of(),
                  1024),
              ignored -> {},
              () -> false);
      assertEquals(1, reply.calls().size());
      assertEquals("project_read_file", reply.calls().getFirst().name());
      assertEquals(Map.of("path", "source.txt"), reply.calls().getFirst().arguments());
      assertEquals("state-1", reply.calls().getFirst().stateId());
      assertEquals(12L, reply.inputTokens());
      assertEquals(4L, reply.outputTokens());
      var waiting = new CountDownLatch(1);
      server.removeContext("/v1/chat/completions");
      server.createContext(
          "/v1/chat/completions",
          exchange -> {
            exchange.getRequestBody().readAllBytes();
            waiting.countDown();
            try {
              Thread.sleep(3000);
            } catch (InterruptedException stopped) {
              Thread.currentThread().interrupt();
            }
            exchange.close();
          });
      var stop = new java.util.concurrent.atomic.AtomicBoolean();
      try (var worker = Executors.newVirtualThreadPerTaskExecutor()) {
        var generation =
            worker.submit(
                () ->
                    gateway.generate(
                        new ProviderGateway.Request(owner, "test-model", List.of(), List.of(), 100),
                        ignored -> {},
                        stop::get));
        assertTrue(waiting.await(5, TimeUnit.SECONDS));
        stop.set(true);
        var failure =
            assertThrows(ExecutionException.class, () -> generation.get(1, TimeUnit.SECONDS));
        assertEquals(
            "cancelled",
            ((dev.blot.application.workspace.WorkspaceFailure) failure.getCause()).code());
      }

    } finally {
      server.stop(0);
    }
  }

  private void respond(HttpExchange exchange, String type, String body) throws java.io.IOException {
    exchange.getRequestBody().readAllBytes();
    byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
    exchange.getResponseHeaders().set("Content-Type", type);
    exchange.sendResponseHeaders(200, bytes.length);
    try (var output = exchange.getResponseBody()) {
      output.write(bytes);
    }
  }
}
