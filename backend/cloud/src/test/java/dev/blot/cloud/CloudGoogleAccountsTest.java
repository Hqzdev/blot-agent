package dev.blot.cloud;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.CloudDatabase;
import dev.blot.infrastructure.workspace.JacksonCodec;
import dev.blot.infrastructure.workspace.security.ArgonPasswordHasher;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

final class CloudGoogleAccountsTest {
  @TempDir Path directory;
  private final JacksonCodec json = new JacksonCodec();
  private final Clock clock = Clock.fixed(Instant.parse("2026-11-04T12:00:00Z"), ZoneOffset.UTC);
  private final String client = "12345-nativewebsite.apps.googleusercontent.com",
      nonce = "n".repeat(43);

  private KeyPair keys() throws Exception {
    var generator = KeyPairGenerator.getInstance("RSA");
    generator.initialize(2048);
    return generator.generateKeyPair();
  }

  private CloudGoogleIdentityVerifier verifier(KeyPair key) {
    return new CloudGoogleIdentityVerifier(
        client,
        json,
        clock,
        kid -> {
          if (!kid.equals("test-key")) throw new CloudFailure(401, "google_identity_invalid");
          return key.getPublic();
        });
  }

  private Map<String, Object> claims() {
    return new HashMap<>(
        Map.of(
            "iss",
            "https://accounts.google.com",
            "aud",
            client,
            "sub",
            "google-subject-123",
            "email",
            "owner@example.org",
            "email_verified",
            true,
            "name",
            "Google owner",
            "nonce",
            nonce,
            "exp",
            clock.instant().plusSeconds(3600).getEpochSecond(),
            "iat",
            clock.instant().getEpochSecond()));
  }

  private String token(KeyPair key, Map<String, Object> claims) throws Exception {
    String header =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(
                json.write(Map.of("alg", "RS256", "kid", "test-key"))
                    .getBytes(StandardCharsets.UTF_8));
    String payload =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(json.write(claims).getBytes(StandardCharsets.UTF_8));
    var signature = Signature.getInstance("SHA256withRSA");
    signature.initSign(key.getPrivate());
    signature.update((header + "." + payload).getBytes(StandardCharsets.US_ASCII));
    return header
        + "."
        + payload
        + "."
        + Base64.getUrlEncoder().withoutPadding().encodeToString(signature.sign());
  }

  @Test
  void verifiesSignatureAudienceNonceAndVerifiedEmail() throws Exception {
    var key = keys();
    var verifier = verifier(key);
    assertEquals("owner@example.org", verifier.verify(token(key, claims()), nonce).email());
    assertThrows(CloudFailure.class, () -> verifier.verify(token(keys(), claims()), nonce));
    assertThrows(CloudFailure.class, () -> verifier.verify(token(key, claims()), "x".repeat(43)));
    for (String field : List.of("aud", "iss", "email_verified", "exp")) {
      var changed = claims();
      changed.put(
          field,
          switch (field) {
            case "email_verified" -> false;
            case "exp" -> 1;
            default -> "untrusted";
          });
      assertThrows(CloudFailure.class, () -> verifier.verify(token(key, changed), nonce));
    }
  }

  @Test
  void googleIdentityPersistsWithoutMergingAnExistingEmail() throws Exception {
    var db = new CloudDatabase(directory.resolve("google.sqlite"));
    var tokens = new CloudTokens(new byte[32]);
    var sessions = new CloudSessions(db, tokens, clock);
    var key = keys();
    var google =
        new CloudGoogleAccounts(
            db, verifier(key), sessions, new ArgonPasswordHasher(), tokens, clock);
    var first = google.login(token(key, claims()), nonce);
    var again = google.login(token(key, claims()), nonce);
    assertEquals(first.ownerID(), again.ownerID());
    assertNotEquals(first.sessionID(), again.sessionID());
    assertTrue(first.bootstrapAllowed());
    var otherSubject = claims();
    otherSubject.put("sub", "different-google-subject");
    assertEquals(
        "google_link_required",
        assertThrows(CloudFailure.class, () -> google.login(token(key, otherSubject), nonce))
            .code());
    assertEquals(
        first.ownerID(), sessions.require("Bearer " + first.accessToken(), false).ownerID());
  }
}
