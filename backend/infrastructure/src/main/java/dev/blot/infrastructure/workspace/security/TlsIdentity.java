package dev.blot.infrastructure.workspace.security;

import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Закрытый ключ находится в PKCS12, пароль — только в Keychain. */
public final class TlsIdentity {
  private final Path keystore;
  private final String password;
  private final String fingerprint;

  public TlsIdentity(Path directory, SecretStore secrets) {
    try {
      Files.createDirectories(directory);
      Files.setPosixFilePermissions(
          directory, java.nio.file.attribute.PosixFilePermissions.fromString("rwx------"));
      keystore = directory.resolve("identity.p12");
      String key = "tls." + new TokenGenerator().digest(directory.toAbsolutePath().toString());
      var stored = secrets.get(key);
      if (Files.exists(keystore) && stored.isEmpty())
        throw new WorkspaceFailure(503, "tls_key_missing", "Восстановите пароль TLS из Keychain");
      password =
          stored.orElseGet(
              () -> {
                String value = new TokenGenerator().token();
                secrets.put(key, value);
                return value;
              });
      if (!Files.exists(keystore)) {
        Path tool = Path.of(System.getProperty("java.home"), "bin", "keytool");
        var process =
            new ProcessBuilder(
                    tool.toString(),
                    "-genkeypair",
                    "-alias",
                    "blot",
                    "-keyalg",
                    "EC",
                    "-groupname",
                    "secp256r1",
                    "-dname",
                    "CN=Blot Local",
                    "-ext",
                    "SAN=ip:127.0.0.1,dns:localhost",
                    "-validity",
                    "3650",
                    "-storetype",
                    "PKCS12",
                    "-keystore",
                    keystore.toString(),
                    "-storepass:file",
                    "/dev/stdin",
                    "-noprompt")
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start();
        try (var input = process.getOutputStream()) {
          input.write((password + "\n").getBytes(StandardCharsets.UTF_8));
        }
        if (!process.waitFor(30, TimeUnit.SECONDS) || process.exitValue() != 0) {
          process.destroyForcibly();
          throw new IllegalStateException("TLS identity generation failed");
        }
        Files.setPosixFilePermissions(
            keystore, java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"));
      }
      var store = KeyStore.getInstance("PKCS12");
      try (var input = Files.newInputStream(keystore)) {
        store.load(input, password.toCharArray());
      }
      fingerprint =
          HexFormat.of()
              .formatHex(
                  MessageDigest.getInstance("SHA-256")
                      .digest(store.getCertificate("blot").getEncoded()));
    } catch (WorkspaceFailure e) {
      throw e;
    } catch (Exception e) {
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      throw new WorkspaceFailure(
          503, "tls_unavailable", "Не удалось создать защищённое подключение");
    }
  }

  public Path keystore() {
    return keystore;
  }

  public String password() {
    return password;
  }

  public String fingerprint() {
    return fingerprint;
  }
}
