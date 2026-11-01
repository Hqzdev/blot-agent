package dev.blot.api.workspace.installation;

import dev.blot.api.workspace.security.TlsConfiguration;
import dev.blot.application.ports.JsonCodec;
import dev.blot.infrastructure.workspace.security.TlsIdentity;
import java.nio.file.*;
import java.util.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
public final class ReadyFileWriter {
  private final Path path;
  private final JsonCodec json;
  private final ObjectProvider<TlsIdentity> tls;
  private final ObjectProvider<TlsConfiguration.BleConnector> ble;

  public ReadyFileWriter(
      @Value("${blot.data-directory:}") String directory,
      @Value("${blot.database:blot.db}") String database,
      JsonCodec json,
      ObjectProvider<TlsIdentity> tls,
      ObjectProvider<TlsConfiguration.BleConnector> ble) {
    this.path =
        (directory.isBlank() ? Path.of(database).toAbsolutePath().getParent() : Path.of(directory))
            .resolve("ready.json");
    this.json = json;
    this.tls = tls;
    this.ble = ble;
  }

  @EventListener
  public void ready(ApplicationReadyEvent event) throws java.io.IOException {
    var context = (WebServerApplicationContext) event.getApplicationContext();
    Files.createDirectories(path.getParent());
    Path idFile = path.getParent().resolve("installation-id");
    if (!Files.exists(idFile))
      Files.writeString(idFile, UUID.randomUUID().toString(), StandardOpenOption.CREATE_NEW);
    var value = new LinkedHashMap<String, Object>();
    value.put("pid", ProcessHandle.current().pid());
    value.put("port", context.getWebServer().getPort());
    value.put("schemaVersion", 2);
    value.put("installationId", Files.readString(idFile).strip());
    var identity = tls.getIfAvailable();
    value.put("scheme", identity == null ? "http" : "https");
    value.put("fingerprint", identity == null ? null : identity.fingerprint());
    value.put("blePort", ble.getIfAvailable() == null ? null : ble.getIfAvailable().port());
    Path temp = Files.createTempFile(path.getParent(), "ready-", ".tmp");
    Files.writeString(temp, json.write(value));
    Files.move(temp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
  }
}
