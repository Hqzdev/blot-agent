package dev.blot.infrastructure.workspace.security;

import dev.blot.application.ports.SecretStore;
import dev.blot.infrastructure.workspace.execution.MacPlatformBridge;
import java.util.*;

/** Секреты приходят через приватный канал приложения, без публичного CLI чтения Keychain. */
public final class MacKeychainSecretStore implements SecretStore {
  private final MacPlatformBridge bridge;

  public MacKeychainSecretStore(MacPlatformBridge bridge) {
    this.bridge = bridge;
  }

  public Optional<String> get(String key) {
    return Optional.ofNullable((String) bridge.request("secret.get", Map.of("key", key)));
  }

  public void put(String key, String value) {
    bridge.request("secret.put", Map.of("key", key, "value", value));
  }

  public void remove(String key) {
    bridge.request("secret.remove", Map.of("key", key));
  }
}
