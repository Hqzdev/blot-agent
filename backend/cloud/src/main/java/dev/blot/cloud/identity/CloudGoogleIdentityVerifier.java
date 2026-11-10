package dev.blot.cloud.identity;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.CloudFailure;
import java.math.BigInteger;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.RSAPublicKeySpec;
import java.time.*;
import java.util.*;

/** Google signs the identity; email text supplied by the browser never identifies an account. */
public final class CloudGoogleIdentityVerifier {
  public record Identity(String subject, String email, String name, String avatarURL) {}

  @FunctionalInterface
  public interface SigningKeys {
    PublicKey key(String kid);
  }

  private final String clientID;
  private final JsonCodec json;
  private final Clock clock;
  private final SigningKeys signingKeys;

  public CloudGoogleIdentityVerifier(String clientID, JsonCodec json, Clock clock) {
    this(clientID, json, clock, new GoogleSigningKeys(json, clock));
  }

  public CloudGoogleIdentityVerifier(
      String clientID, JsonCodec json, Clock clock, SigningKeys signingKeys) {
    this.clientID = clientID;
    this.json = json;
    this.clock = clock;
    this.signingKeys = signingKeys;
  }

  public Identity verify(String token, String nonce) {
    if (clientID == null || clientID.isBlank()) throw new CloudFailure(503, "google_unconfigured");
    if (token == null
        || token.length() > 16_384
        || nonce == null
        || !nonce.matches("[A-Za-z0-9_-]{43}")) throw invalid();
    try {
      String[] pieces = token.split("\\.", -1);
      if (pieces.length != 3 || Arrays.stream(pieces).anyMatch(p -> !p.matches("[A-Za-z0-9_-]+")))
        throw invalid();
      Map<?, ?> header =
          json.read(
              new String(Base64.getUrlDecoder().decode(pieces[0]), StandardCharsets.UTF_8),
              Map.class);
      if (!"RS256".equals(header.get("alg"))
          || !(header.get("kid") instanceof String kid)
          || kid.length() > 200) throw invalid();
      var verifier = Signature.getInstance("SHA256withRSA");
      verifier.initVerify(signingKeys.key(kid));
      verifier.update((pieces[0] + "." + pieces[1]).getBytes(StandardCharsets.US_ASCII));
      if (!verifier.verify(Base64.getUrlDecoder().decode(pieces[2]))) throw invalid();
      Map<?, ?> claims =
          json.read(
              new String(Base64.getUrlDecoder().decode(pieces[1]), StandardCharsets.UTF_8),
              Map.class);
      boolean audience =
          clientID.equals(claims.get("aud"))
              || (claims.get("aud") instanceof List<?> list
                  && list.size() == 1
                  && list.contains(clientID));
      if (!Set.of("accounts.google.com", "https://accounts.google.com").contains(claims.get("iss"))
          || !audience
          || (claims.get("azp") != null && !clientID.equals(claims.get("azp")))
          || !nonce.equals(claims.get("nonce"))
          || !(claims.get("exp") instanceof Number exp)
          || exp.longValue() <= clock.instant().getEpochSecond()
          || !(claims.get("iat") instanceof Number issued)
          || issued.longValue() > clock.instant().plusSeconds(60).getEpochSecond()
          || !Boolean.TRUE.equals(claims.get("email_verified"))
          || !(claims.get("sub") instanceof String subject)
          || subject.isBlank()
          || subject.length() > 255
          || !(claims.get("email") instanceof String email)) throw invalid();
      String name =
          claims.get("name") instanceof String value && !value.isBlank() && value.length() <= 200
              ? value
              : email;
      return new Identity(
          subject,
          CloudTokens.email(email),
          name,
          CloudProfileAvatar.google(claims.get("picture")));
    } catch (CloudFailure failure) {
      throw failure;
    } catch (Exception failure) {
      throw invalid();
    }
  }

  private static CloudFailure invalid() {
    return new CloudFailure(401, "google_identity_invalid");
  }

  private static final class GoogleSigningKeys implements SigningKeys {
    private final JsonCodec json;
    private final Clock clock;
    private final HttpClient http =
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();
    private Map<String, PublicKey> cached = Map.of();
    private Instant expires = Instant.MIN;
    private Instant fetched = Instant.MIN;

    GoogleSigningKeys(JsonCodec json, Clock clock) {
      this.json = json;
      this.clock = clock;
    }

    public synchronized PublicKey key(String kid) {
      if (expires.isBefore(clock.instant())
          || (!cached.containsKey(kid) && fetched.plusSeconds(60).isBefore(clock.instant())))
        refresh();
      PublicKey result = cached.get(kid);
      if (result == null) throw invalid();
      return result;
    }

    private void refresh() {
      try {
        var request =
            HttpRequest.newBuilder(URI.create("https://www.googleapis.com/oauth2/v3/certs"))
                .timeout(Duration.ofSeconds(10))
                .GET()
                .build();
        var response = http.send(request, HttpResponse.BodyHandlers.ofInputStream());
        byte[] bytes;
        try (var body = response.body()) {
          bytes = body.readNBytes(65_537);
        }
        if (response.statusCode() != 200 || bytes.length > 65_536)
          throw new CloudFailure(503, "google_unavailable");
        Map<?, ?> root = json.read(new String(bytes, StandardCharsets.UTF_8), Map.class);
        if (!(root.get("keys") instanceof List<?> keys) || keys.size() > 20) throw invalid();
        Map<String, PublicKey> next = new HashMap<>();
        for (Object item : keys)
          if (item instanceof Map<?, ?> key
              && "RSA".equals(key.get("kty"))
              && "sig".equals(key.get("use"))
              && "RS256".equals(key.get("alg"))
              && key.get("kid") instanceof String id
              && key.get("n") instanceof String n
              && key.get("e") instanceof String e) {
            var modulus = new BigInteger(1, Base64.getUrlDecoder().decode(n));
            if (modulus.bitLength() < 2048 || modulus.bitLength() > 8192) throw invalid();
            next.put(
                id,
                KeyFactory.getInstance("RSA")
                    .generatePublic(
                        new RSAPublicKeySpec(
                            modulus, new BigInteger(1, Base64.getUrlDecoder().decode(e)))));
          }
        if (next.isEmpty()) throw invalid();
        cached = Map.copyOf(next);
        fetched = clock.instant();
        expires = fetched.plusSeconds(3600);
      } catch (InterruptedException failure) {
        Thread.currentThread().interrupt();
        throw new CloudFailure(503, "google_unavailable");
      } catch (Exception failure) {
        throw new CloudFailure(503, "google_unavailable");
      }
    }
  }
}
