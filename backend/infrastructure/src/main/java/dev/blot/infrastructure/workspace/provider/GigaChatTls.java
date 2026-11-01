package dev.blot.infrastructure.workspace.provider;

import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import java.net.http.HttpClient;
import java.security.*;
import java.time.Duration;
import java.util.*;
import javax.net.ssl.*;

/** Дополнительное доверие действует только в HTTP-клиенте данного аккаунта к GigaChat. */
final class GigaChatTls {
  private record Entry(String pem, HttpClient client) {}

  private final SecretStore secrets;
  private final HttpClient standard;
  private final Map<UUID, Entry> clients = new HashMap<>();

  GigaChatTls(SecretStore secrets, HttpClient standard) {
    this.secrets = secrets;
    this.standard = standard;
  }

  synchronized HttpClient client(UUID owner) {
    String pem = secrets.get("provider.ca." + owner).orElse(null);
    var cached = clients.get(owner);
    if (pem == null) {
      if (cached != null) {
        clients.remove(owner);
        cached.client().shutdown();
      }
      return standard;
    }
    if (cached != null && cached.pem().equals(pem)) return cached.client();
    try {
      var roots = KeyStore.getInstance(KeyStore.getDefaultType());
      roots.load(null, null);
      var defaults = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      defaults.init((KeyStore) null);
      int index = 0;
      for (var manager : defaults.getTrustManagers())
        if (manager instanceof X509TrustManager trust)
          for (var certificate : trust.getAcceptedIssuers())
            roots.setCertificateEntry("default-" + index++, certificate);
      for (var certificate : PemCertificates.parse(pem))
        roots.setCertificateEntry("selected-" + index++, certificate);
      var trust = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      trust.init(roots);
      var tls = SSLContext.getInstance("TLS");
      tls.init(null, trust.getTrustManagers(), null);
      var client =
          HttpClient.newBuilder()
              .connectTimeout(Duration.ofSeconds(20))
              .sslContext(tls)
              .followRedirects(HttpClient.Redirect.NEVER)
              .build();
      clients.put(owner, new Entry(pem, client));
      if (cached != null) cached.client().shutdown();
      return client;
    } catch (GeneralSecurityException | java.io.IOException failure) {
      throw new WorkspaceFailure(
          503, "provider_certificate_invalid", "Повторно выберите сертификат GigaChat на Mac");
    }
  }
}
