package dev.blot.infrastructure.workspace.provider;

import com.sun.net.httpserver.*;
import dev.blot.application.ports.*;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.providers.ProviderCertificateService;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.infrastructure.workspace.provider.GigaChatTls;
import dev.blot.infrastructure.workspace.provider.PemCertificates;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

import static org.junit.jupiter.api.Assertions.*;

class GigaChatTlsTest {
  @TempDir Path directory;

  @Test
  void selectedCaIsScopedToOwnerAndHostnameValidationRemainsEnabled() throws Exception {
    String password = "test-password";
    Path keyStore = directory.resolve("fixture.p12");
    var process =
        new ProcessBuilder(
                Path.of(System.getProperty("java.home"), "bin", "keytool").toString(),
                "-genkeypair",
                "-noprompt",
                "-alias",
                "fixture",
                "-keyalg",
                "EC",
                "-groupname",
                "secp256r1",
                "-dname",
                "CN=Fixture CA",
                "-ext",
                "BC=ca:true",
                "-ext",
                "SAN=dns:localhost",
                "-validity",
                "2",
                "-storetype",
                "PKCS12",
                "-keystore",
                keyStore.toString(),
                "-storepass",
                password)
            .redirectErrorStream(true)
            .start();
    String output =
        new String(
            process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    assertTrue(process.waitFor(10, TimeUnit.SECONDS));
    assertEquals(0, process.exitValue(), output);
    var keys = KeyStore.getInstance("PKCS12");
    try (var input = Files.newInputStream(keyStore)) {
      keys.load(input, password.toCharArray());
    }
    var keyManager = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    keyManager.init(keys, password.toCharArray());
    var serverTls = SSLContext.getInstance("TLS");
    serverTls.init(keyManager.getKeyManagers(), null, null);
    var server = HttpsServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.setHttpsConfigurator(new HttpsConfigurator(serverTls));
    server.createContext(
        "/",
        exchange -> {
          exchange.sendResponseHeaders(200, 2);
          try (var body = exchange.getResponseBody()) {
            body.write(new byte[] {'o', 'k'});
          }
        });
    var values = new ConcurrentHashMap<String, String>();
    SecretStore secrets =
        new SecretStore() {
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
    UUID owner = UUID.randomUUID();
    String pem =
        "-----BEGIN CERTIFICATE-----\n"
            + Base64.getMimeEncoder(64, new byte[] {10})
                .encodeToString(keys.getCertificate("fixture").getEncoded())
            + "\n-----END CERTIFICATE-----\n";
    var service = new ProviderCertificateService(secrets, new PemCertificates());
    assertThrows(
        WorkspaceFailure.class,
        () -> service.save(new Actor(owner, null, UUID.randomUUID(), false), pem));
    var details = service.save(new Actor(owner, null, null, true), pem);
    assertEquals(1, details.size());
    assertTrue(details.getFirst().sha256().matches("[0-9A-F:]{95}"));
    var standard = HttpClient.newHttpClient();
    var clients = new GigaChatTls(secrets, standard);
    var trusted = clients.client(owner);
    server.start();
    try {
      int port = server.getAddress().getPort();
      assertEquals(
          200,
          trusted
              .send(
                  HttpRequest.newBuilder(URI.create("https://localhost:" + port + "/")).build(),
                  HttpResponse.BodyHandlers.ofString())
              .statusCode());
      assertThrows(
          SSLHandshakeException.class,
          () ->
              clients
                  .client(UUID.randomUUID())
                  .send(
                      HttpRequest.newBuilder(URI.create("https://localhost:" + port + "/")).build(),
                      HttpResponse.BodyHandlers.ofString()));
      assertThrows(
          SSLHandshakeException.class,
          () ->
              trusted.send(
                  HttpRequest.newBuilder(URI.create("https://127.0.0.1:" + port + "/")).build(),
                  HttpResponse.BodyHandlers.ofString()));
    } finally {
      server.stop(0);
      trusted.close();
      standard.close();
    }
  }
}
