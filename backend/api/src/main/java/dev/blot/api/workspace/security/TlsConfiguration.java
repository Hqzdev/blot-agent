package dev.blot.api.workspace.security;

import dev.blot.application.ports.SecretStore;
import dev.blot.infrastructure.workspace.security.TlsIdentity;
import java.net.*;
import java.nio.file.*;
import org.apache.catalina.connector.Connector;
import org.apache.tomcat.util.net.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.tomcat.servlet.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.*;
import org.springframework.context.annotation.*;

@Configuration
@ConditionalOnProperty(name = "blot.tls.enabled", havingValue = "true")
public class TlsConfiguration {
  @Bean
  TlsIdentity tlsIdentity(@Value("${blot.data-directory}") String directory, SecretStore secrets) {
    return new TlsIdentity(Path.of(directory).resolve("tls"), secrets);
  }

  @Bean
  BleConnector bleConnector(TlsIdentity identity) throws UnknownHostException {
    var connector = new Connector("org.apache.coyote.http11.Http11NioProtocol");
    connector.setPort(0);
    connector.setScheme("https");
    connector.setSecure(true);
    connector.setProperty("address", "127.0.0.1");
    connector.setProperty("SSLEnabled", "true");
    var host = new SSLHostConfig();
    host.setProtocols("TLSv1.3,TLSv1.2");
    var certificate = new SSLHostConfigCertificate(host, SSLHostConfigCertificate.Type.EC);
    certificate.setCertificateKeystoreFile(identity.keystore().toString());
    certificate.setCertificateKeystoreType("PKCS12");
    certificate.setCertificateKeystorePassword(identity.password());
    host.addCertificate(certificate);
    connector.addSslHostConfig(host);
    return new BleConnector(connector);
  }

  @Bean
  WebServerFactoryCustomizer<TomcatServletWebServerFactory> tlsCustomizer(
      TlsIdentity identity, BleConnector ble) {
    return factory -> {
      var ssl = new Ssl();
      ssl.setEnabled(true);
      ssl.setKeyStore(identity.keystore().toUri().toString());
      ssl.setKeyStoreType("PKCS12");
      ssl.setKeyStorePassword(identity.password());
      ssl.setEnabledProtocols(new String[] {"TLSv1.3", "TLSv1.2"});
      factory.setSsl(ssl);
      factory.addAdditionalConnectors(ble.connector());
    };
  }

  public record BleConnector(Connector connector) {
    public int port() {
      return connector.getLocalPort();
    }
  }
}
