package dev.blot.cloud;

import dev.blot.application.ports.*;
import dev.blot.cloud.execution.CloudLeases;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.model.*;
import dev.blot.cloud.relay.*;
import dev.blot.cloud.storage.CloudDatabase;
import dev.blot.infrastructure.workspace.JacksonCodec;
import dev.blot.infrastructure.workspace.provider.*;
import dev.blot.infrastructure.workspace.security.ArgonPasswordHasher;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.file.Path;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;

@Configuration
public class CloudConfiguration {
  @Bean
  Clock clock() {
    return Clock.systemUTC();
  }

  @Bean
  CloudDatabase database(@Value("${blot.cloud.database}") String path) {
    return new CloudDatabase(Path.of(path));
  }

  @Bean
  CloudSecrets secrets() {
    return new CloudSecrets(CloudRuntimeEnvironment.load(System.getenv()));
  }

  @Bean
  CloudTokens tokens(CloudSecrets secrets) {
    String key =
        secrets
            .get("cloud.challenge_key")
            .orElseThrow(
                () ->
                    new IllegalStateException(
                        "Configure BLOT_CLOUD_CHALLENGE_KEY_FILE with a persistent base64 key"));
    try {
      return new CloudTokens(Base64.getDecoder().decode(key));
    } catch (IllegalArgumentException failure) {
      throw new IllegalStateException(
          "Cloud challenge key must be base64 with at least 32 decoded bytes");
    }
  }

  @Bean
  JsonCodec json() {
    return new JacksonCodec();
  }

  @Bean
  PasswordHasher passwords() {
    return new ArgonPasswordHasher();
  }

  @Bean
  EmailSender email(CloudSecrets secrets) {
    return new SmtpEmailSender(secrets);
  }

  @Bean
  CloudRateLimiter rates(CloudDatabase db, CloudTokens tokens, Clock clock) {
    return new CloudRateLimiter(db, tokens, clock);
  }

  @Bean
  CloudSessions sessions(CloudDatabase db, CloudTokens tokens, Clock clock) {
    return new CloudSessions(db, tokens, clock);
  }

  @Bean
  CloudBrowserAuthorization browserAuthorization(
      CloudDatabase db, CloudTokens tokens, CloudSessions sessions, Clock clock) {
    return new CloudBrowserAuthorization(db, tokens, sessions, clock);
  }

  @Bean
  CloudEmailChallenges challenges(
      CloudDatabase db,
      CloudTokens tokens,
      EmailSender email,
      CloudRateLimiter rates,
      Clock clock) {
    return new CloudEmailChallenges(db, tokens, email, rates, clock);
  }

  @Bean
  CloudAccounts accounts(
      CloudDatabase db,
      PasswordHasher passwords,
      CloudEmailChallenges challenges,
      CloudSessions sessions,
      Clock clock) {
    return new CloudAccounts(db, passwords, challenges, sessions, clock);
  }

  @Bean
  CloudGoogleAccounts googleAccounts(
      CloudDatabase db,
      CloudSecrets secrets,
      JsonCodec json,
      Clock clock,
      CloudSessions sessions,
      PasswordHasher passwords,
      CloudTokens tokens) {
    var verifier =
        new CloudGoogleIdentityVerifier(
            secrets.get("google.web_client_id").orElse(""), json, clock);
    return new CloudGoogleAccounts(db, verifier, sessions, passwords, tokens, clock);
  }

  @Bean
  CloudDevices devices(CloudDatabase db, Clock clock) {
    return new CloudDevices(db, clock);
  }

  @Bean
  CloudPairings pairings(CloudDatabase db, CloudTokens tokens, Clock clock) {
    return new CloudPairings(db, tokens, clock);
  }

  @Bean
  CloudDeviceRevocations revocations(CloudDatabase db, CloudTokens tokens, JsonCodec json) {
    return new CloudDeviceRevocations(db, tokens, json);
  }

  @Bean
  CloudRelay relay(
      CloudDatabase db,
      JsonCodec json,
      CloudTokens tokens,
      Clock clock,
      @Value("${blot.cloud.relay-bytes}") long maximumBytes) {
    return new CloudRelay(db, json, tokens, clock, maximumBytes);
  }

  @Bean
  CloudEncryptedBlobs blobs(CloudDatabase db, CloudTokens tokens, Clock clock) {
    return new CloudEncryptedBlobs(db, tokens, clock);
  }

  @Bean
  CloudSnapshots snapshots(CloudDatabase db, JsonCodec json, Clock clock) {
    return new CloudSnapshots(db, json, clock);
  }

  @Bean
  CloudLeases leases(CloudDatabase db, Clock clock) {
    return new CloudLeases(db, clock, Duration.ofSeconds(90));
  }

  @Bean
  ProviderGateway provider(CloudSecrets secrets, JsonCodec json, Clock clock) {
    return new GigaChatGateway(
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(20))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build(),
        json,
        secrets,
        URI.create("https://gigachat.devices.sberbank.ru/api/v1/"),
        URI.create("https://ngw.devices.sberbank.ru:9443/api/v2/oauth"),
        clock);
  }

  @Bean
  CloudModelQuota quota(
      CloudDatabase db, Clock clock, @Value("${blot.cloud.quota-tokens}") long tokens) {
    return new CloudModelQuota(db, clock, tokens);
  }

  @Bean
  CloudModelGateway model(ProviderGateway provider, CloudModelQuota quota) {
    return new CloudModelGateway(provider, quota);
  }
}
