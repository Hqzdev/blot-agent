package dev.blot.infrastructure.workspace.security;

import dev.blot.application.ports.PasswordHasher;
import java.security.*;
import java.util.*;
import org.bouncycastle.crypto.generators.Argon2BytesGenerator;
import org.bouncycastle.crypto.params.Argon2Parameters;

public final class ArgonPasswordHasher implements PasswordHasher {
  private final SecureRandom random = new SecureRandom();

  public String hash(String password) {
    byte[] salt = new byte[16];
    random.nextBytes(salt);
    return "argon2id$65536$3$1$"
        + Base64.getEncoder().encodeToString(salt)
        + "$"
        + Base64.getEncoder().encodeToString(derive(password, salt));
  }

  public boolean matches(String password, String hash) {
    try {
      String[] parts = hash.split("\\$");
      if (parts.length != 6
          || !parts[0].equals("argon2id")
          || !parts[1].equals("65536")
          || !parts[2].equals("3")
          || !parts[3].equals("1")) return false;
      return MessageDigest.isEqual(
          derive(password, Base64.getDecoder().decode(parts[4])),
          Base64.getDecoder().decode(parts[5]));
    } catch (IllegalArgumentException e) {
      return false;
    }
  }

  private byte[] derive(String password, byte[] salt) {
    var params =
        new Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withVersion(Argon2Parameters.ARGON2_VERSION_13)
            .withMemoryAsKB(65536)
            .withIterations(3)
            .withParallelism(1)
            .withSalt(salt)
            .build();
    var generator = new Argon2BytesGenerator();
    generator.init(params);
    byte[] hash = new byte[32];
    char[] chars = password.toCharArray();
    try {
      generator.generateBytes(chars, hash);
      return hash;
    } finally {
      Arrays.fill(chars, '\0');
    }
  }
}
