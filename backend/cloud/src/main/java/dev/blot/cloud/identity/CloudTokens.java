package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class CloudTokens {
  private final SecureRandom random = new SecureRandom();
  private final byte[] challengeKey;

  public CloudTokens(byte[] challengeKey) {
    if (challengeKey.length < 32)
      throw new IllegalArgumentException("Cloud challenge key requires 32 bytes");
    this.challengeKey = challengeKey.clone();
  }

  public String random() {
    byte[] value = new byte[32];
    random.nextBytes(value);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
  }

  public String code() {
    return "%06d".formatted(random.nextInt(1_000_000));
  }

  public String digest(String value) {
    return digest(value.getBytes(StandardCharsets.UTF_8));
  }

  public String digest(byte[] value) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
    } catch (GeneralSecurityException impossible) {
      throw new IllegalStateException(impossible);
    }
  }

  public String challengeDigest(UUID id, String code) {
    try {
      var mac = Mac.getInstance("HmacSHA256");
      mac.init(new SecretKeySpec(challengeKey, "HmacSHA256"));
      return HexFormat.of()
          .formatHex(mac.doFinal((id + ":" + code).getBytes(StandardCharsets.UTF_8)));
    } catch (GeneralSecurityException impossible) {
      throw new IllegalStateException(impossible);
    }
  }

  public boolean equal(String a, String b) {
    return MessageDigest.isEqual(
        a.getBytes(StandardCharsets.US_ASCII), b.getBytes(StandardCharsets.US_ASCII));
  }

  public static String email(String value) {
    if (value == null || value.length() > 254 || !value.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+"))
      throw new CloudFailure(400, "invalid_email");
    return value.strip().toLowerCase(Locale.ROOT);
  }

  public static void password(String value) {
    if (value == null || value.length() < 8 || value.length() > 128)
      throw new CloudFailure(400, "invalid_password");
  }
}
