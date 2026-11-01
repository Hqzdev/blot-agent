package dev.blot.application.workspace.identity;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

public final class TokenGenerator {
  private final SecureRandom random = new SecureRandom();

  public String token() {
    byte[] bytes = new byte[32];
    random.nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  public String code() {
    return String.format(Locale.ROOT, "%06d", random.nextInt(1_000_000));
  }

  public String digest(String value) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  public boolean matches(String value, String hash) {
    return value != null
        && MessageDigest.isEqual(
            digest(value).getBytes(StandardCharsets.US_ASCII),
            hash.getBytes(StandardCharsets.US_ASCII));
  }
}
