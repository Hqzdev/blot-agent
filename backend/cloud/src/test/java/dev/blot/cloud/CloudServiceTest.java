package dev.blot.cloud;

import static org.junit.jupiter.api.Assertions.*;

import dev.blot.application.ports.EmailSender;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.cloud.execution.CloudLeases;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.model.CloudModelGateway;
import dev.blot.cloud.model.CloudModelQuota;
import dev.blot.cloud.relay.*;
import dev.blot.cloud.storage.CloudDatabase;
import dev.blot.infrastructure.workspace.JacksonCodec;
import dev.blot.infrastructure.workspace.security.ArgonPasswordHasher;
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.*;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;

final class CloudServiceTest {
  @TempDir Path directory;
  private static final String EMAIL = "apple-test@example.org",
      PASSWORD = "test-password-very-long";

  private static final class MutableClock extends Clock {
    Instant now = Instant.parse("2026-11-03T12:00:00Z");

    public ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    public Clock withZone(ZoneId zone) {
      return this;
    }

    public Instant instant() {
      return now;
    }

    void advance(Duration duration) {
      now = now.plus(duration);
    }
  }

  private static final class Mailbox implements EmailSender {
    String code;

    public void sendCode(String email, String code, String purpose) {
      this.code = code;
    }
  }

  private record Device(CloudActor actor, KeyPair keys) {}

  private final MutableClock clock = new MutableClock();
  private final Mailbox mail = new Mailbox();
  private final CloudTokens tokens = new CloudTokens(new byte[32]);
  private final JacksonCodec json = new JacksonCodec();
  private CloudDatabase db;
  private CloudSessions sessions;
  private CloudAccounts accounts;
  private CloudDevices devices;
  private CloudPairings pairings;
  private CloudRelay relay;

  @BeforeEach
  void setup() {
    db = new CloudDatabase(directory.resolve("cloud.sqlite"));
    sessions = new CloudSessions(db, tokens, clock);
    var rates = new CloudRateLimiter(db, tokens, clock);
    var challenges = new CloudEmailChallenges(db, tokens, mail, rates, clock);
    accounts = new CloudAccounts(db, new ArgonPasswordHasher(), challenges, sessions, clock);
    devices = new CloudDevices(db, clock);
    pairings = new CloudPairings(db, tokens, clock);
    relay = new CloudRelay(db, json, tokens, clock);
  }

  @Test
  void browserAuthorizationRequiresPKCEAndBindsOneNativeClient() throws Exception {
    accounts.register(EMAIL, PASSWORD, "Tester");
    var verified = accounts.verify(EMAIL, mail.code);
    var browser = new CloudBrowserAuthorization(db, tokens, sessions, clock);
    String verifier = "a".repeat(43);
    String challenge =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(
                java.security.MessageDigest.getInstance("SHA-256")
                    .digest(verifier.getBytes(StandardCharsets.US_ASCII)));
    failCode(
        "browser_authorization_invalid",
        () -> browser.issue(actor(verified), "blot-ios", "https://attacker.example/", challenge));
    var code =
        browser.issue(actor(verified), "blot-ios", "blot-agent-ios:/oauth/account", challenge);
    failCode(
        "browser_authorization_invalid",
        () ->
            browser.exchange(
                code.code(), "b".repeat(43), "blot-ios", "blot-agent-ios:/oauth/account"));
    failCode(
        "browser_authorization_invalid",
        () ->
            browser.exchange(
                code.code(), verifier, "blot-macos", "blot-agent-macos:/oauth/account"));
    var nativeSession =
        browser.exchange(code.code(), verifier, "blot-ios", "blot-agent-ios:/oauth/account");
    assertEquals(verified.ownerID(), nativeSession.ownerID());
    assertNotEquals(verified.sessionID(), nativeSession.sessionID());
    assertTrue(nativeSession.bootstrapAllowed());
    failCode(
        "browser_authorization_invalid",
        () -> browser.exchange(code.code(), verifier, "blot-ios", "blot-agent-ios:/oauth/account"));
    var expired =
        browser.issue(actor(verified), "blot-ios", "blot-agent-ios:/oauth/account", challenge);
    clock.advance(Duration.ofSeconds(61));
    failCode(
        "browser_authorization_invalid",
        () ->
            browser.exchange(
                expired.code(), verifier, "blot-ios", "blot-agent-ios:/oauth/account"));
  }

  @Test
  void emailVerificationRotatingSessionsAndDeviceProofAreRequired() throws Exception {
    accounts.register(EMAIL, PASSWORD, "Tester");
    failCode("email_unverified", () -> accounts.login(EMAIL, PASSWORD));
    String correct = mail.code;
    failCode(
        "code_expired_or_invalid",
        () -> accounts.verify(EMAIL, correct.equals("000000") ? "111111" : "000000"));
    var first = accounts.verify(EMAIL, correct);
    var unbound = actor(first);
    failCode(
        "device_pairing_required", () -> sessions.require("Bearer " + first.accessToken(), true));
    KeyPair key = key();
    UUID id = UUID.randomUUID();
    devices.bootstrap(unbound, registration(unbound, id, key, "DESKTOP"));
    var bound = sessions.require("Bearer " + first.accessToken(), true);
    assertEquals(id, bound.deviceID());
    var rotated = sessions.refresh(first.refreshToken());
    failCode("session_expired", () -> sessions.require("Bearer " + first.accessToken(), true));
    failCode("session_expired", () -> sessions.refresh(first.refreshToken()));
    assertEquals(id, sessions.require("Bearer " + rotated.accessToken(), true).deviceID());
    var login = accounts.login(EMAIL, PASSWORD);
    var loginActor = actor(login);
    failCode(
        "device_pairing_required",
        () ->
            devices.bootstrap(
                loginActor, registration(loginActor, UUID.randomUUID(), key, "DESKTOP")));
    var challenge = sessions.challenge(loginActor);
    byte[] proof =
        sign(
            key,
            CloudDeviceProof.message(
                "BLOT-SESSION-BIND-1",
                List.of(login.sessionID(), id),
                List.of(challenge.nonce().getBytes(StandardCharsets.US_ASCII))));
    sessions.bind(loginActor, id, challenge.nonce(), proof);
    failCode("challenge_expired", () -> sessions.bind(loginActor, id, challenge.nonce(), proof));
    assertEquals(id, sessions.require("Bearer " + login.accessToken(), true).deviceID());
    accounts.requestReset(EMAIL);
    String reset = mail.code;
    accounts.reset(EMAIL, reset, "a-new-valid-password");
    failCode("session_expired", () -> sessions.refresh(rotated.refreshToken()));
    failCode("wrong_credentials", () -> accounts.login(EMAIL, PASSWORD));
    assertNotNull(accounts.login(EMAIL, "a-new-valid-password"));
    String rows =
        db.transact(
            tx ->
                json.write(
                    tx.query(
                        "SELECT access_hash, refresh_hash FROM sessions",
                        r -> List.of(r.getString(1), r.getString(2)))));
    assertFalse(rows.contains(rotated.accessToken()));
    assertFalse(rows.contains(rotated.refreshToken()));
  }

  @Test
  void pairingRequiresOwnerConfirmationAndCannotReplaceCandidate() throws Exception {
    Device owner = bootstrap();
    var invite = pairings.start(owner.actor());
    var login = accounts.login(EMAIL, PASSWORD);
    var candidateActor = actor(login);
    KeyPair candidateKey = key();
    UUID candidateID = UUID.randomUUID();
    var registration = claimRegistration(invite, candidateID, candidateKey);
    failCode(
        "pairing_denied",
        () -> pairings.claim(candidateActor, invite.id(), "incorrect", registration));
    var claimed = pairings.claim(candidateActor, invite.id(), invite.secret(), registration);
    assertEquals("WAITING_CONFIRMATION", claimed.state());
    failCode("pairing_waiting_confirmation", () -> pairings.result(candidateActor, invite.id()));
    failCode(
        "device_pairing_required", () -> sessions.require("Bearer " + login.accessToken(), true));
    UUID otherID = UUID.randomUUID();
    KeyPair otherKey = key();
    failCode(
        "pairing_already_claimed",
        () ->
            pairings.claim(
                candidateActor,
                invite.id(),
                invite.secret(),
                claimRegistration(invite, otherID, otherKey)));
    byte[] encryptedGrant = new byte[64];
    new SecureRandom().nextBytes(encryptedGrant);
    byte[] proof =
        sign(
            owner.keys(),
            CloudPairings.approvalMessage(
                owner.actor().workspaceID(),
                invite.id(),
                owner.actor().deviceID(),
                candidateID,
                1,
                raw(candidateKey),
                raw(candidateKey),
                encryptedGrant));
    var approval = new CloudPairings.Approval(invite.id(), candidateID, 1, encryptedGrant, proof);
    var approved = pairings.approve(owner.actor(), approval);
    assertArrayEquals(encryptedGrant, approved.wrappedKeys());
    assertEquals(candidateID, pairings.result(candidateActor, invite.id()).deviceID());
    assertEquals(candidateID, sessions.require("Bearer " + login.accessToken(), true).deviceID());
    assertArrayEquals(
        approved.wrappedKeys(), pairings.approve(owner.actor(), approval).wrappedKeys());
    assertEquals(2, devices.list(owner.actor()).size());
  }

  @Test
  void relayIsDurableIdempotentSignedAndExpiresWithExplicitReplayFailure() throws Exception {
    Device owner = bootstrap();
    UUID changeID = UUID.randomUUID();
    CloudPacket packet = packet(owner, changeID, 1, 1);
    assertEquals(changeID, relay.upload(owner.actor(), packet));
    assertEquals(changeID, relay.upload(owner.actor(), packet));
    var limitedRelay = new CloudRelay(db, json, tokens, clock, json.write(packet).length() + 1L);
    failCode(
        "relay_quota_exceeded",
        () -> limitedRelay.upload(owner.actor(), packet(owner, UUID.randomUUID(), 2, 1)));
    var restarted =
        new CloudRelay(new CloudDatabase(directory.resolve("cloud.sqlite")), json, tokens, clock);
    assertTrue(restarted.accepted(owner.actor(), changeID));
    var batch = restarted.pull(owner.actor(), 0, 10);
    assertEquals(1, batch.deliveries().size());
    assertFalse(batch.hasMore());
    restarted.acknowledge(owner.actor(), batch.cursor());
    restarted.acknowledge(owner.actor(), 0);
    failCode(
        "command_conflict", () -> restarted.upload(owner.actor(), packet(owner, changeID, 1, 1)));
    failCode(
        "sequence_gap",
        () -> restarted.upload(owner.actor(), packet(owner, UUID.randomUUID(), 3, 1)));
    byte[] corrupted = packet.ciphertext();
    corrupted[0] ^= 1;
    var tampered =
        new CloudPacket(
            packet.kind(),
            packet.workspaceID(),
            packet.originDeviceID(),
            packet.changeID(),
            packet.sequence(),
            packet.keyEpoch(),
            corrupted,
            packet.signature());
    failCode("device_proof_invalid", () -> restarted.upload(owner.actor(), tampered));
    clock.advance(Duration.ofDays(31));
    restarted.purgeExpired();
    failCode("replay_unavailable", () -> restarted.pull(owner.actor(), 0, 10));
    assertTrue(restarted.accepted(owner.actor(), changeID));
    restarted.upload(owner.actor(), packet); // Same ciphertext receipt survives TTL.
    restarted.upload(owner.actor(), packet(owner, UUID.randomUUID(), 2, 1));
    assertEquals(1, restarted.pull(owner.actor(), batch.cursor(), 10).deliveries().size());
  }

  @Test
  void snapshotDonorMustBeCurrentSignedAndCompleteBeforePublication() throws Exception {
    Device donor = bootstrap(), receiver = paired(donor);
    // Reopen an existing v1 database without replacing its account, device or relay data.
    db.transact(
        tx -> {
          tx.execute("DROP TABLE snapshot_requests");
          tx.execute("DROP TABLE browser_authorizations");
          tx.execute("DROP INDEX accounts_google_subject");
          tx.execute("ALTER TABLE accounts DROP COLUMN google_subject");
          tx.execute("PRAGMA user_version = 1");
          return null;
        });
    db = new CloudDatabase(directory.resolve("cloud.sqlite"));
    var snapshots = new CloudSnapshots(db, json, clock);
    var blobs = new CloudEncryptedBlobs(db, tokens, clock);
    relay.upload(donor.actor(), packet(donor, UUID.randomUUID(), 1, 1));
    long cursor = relay.pull(donor.actor(), 0, 10).cursor();
    UUID requestID = UUID.randomUUID(), snapshotID = UUID.randomUUID();
    var request = snapshots.request(receiver.actor(), requestID, 0);
    assertNull(request.offer());
    assertEquals(request, snapshots.request(receiver.actor(), requestID, 0));
    failCode("command_conflict", () -> snapshots.request(receiver.actor(), requestID, 1));
    assertEquals(1, snapshots.pending(donor.actor()).size());
    assertTrue(snapshots.pending(receiver.actor()).isEmpty());
    byte[] ciphertext = new byte[300_000];
    new SecureRandom().nextBytes(ciphertext);
    String digest = tokens.digest(ciphertext);
    byte[] packetSignature = sign(donor.keys(), ciphertext);
    var unsigned =
        new CloudSnapshots.Offer(
            requestID,
            snapshotID,
            donor.actor().deviceID(),
            1,
            cursor,
            ciphertext.length,
            2,
            digest,
            packetSignature,
            null);
    var offer =
        new CloudSnapshots.Offer(
            requestID,
            snapshotID,
            donor.actor().deviceID(),
            1,
            cursor,
            ciphertext.length,
            2,
            digest,
            packetSignature,
            sign(donor.keys(), CloudSnapshots.proof(donor.actor().workspaceID(), unsigned)));
    failCode("snapshot_cursor_unavailable", () -> snapshots.publish(donor.actor(), offer));
    relay.acknowledge(donor.actor(), cursor);
    failCode("snapshot_chunks_missing", () -> snapshots.publish(donor.actor(), offer));
    blobs.put(
        donor.actor(),
        new CloudEncryptedBlobs.Chunk(
            snapshotID, 0, 2, Arrays.copyOfRange(ciphertext, 0, 262_144)));
    failCode("snapshot_chunks_missing", () -> snapshots.publish(donor.actor(), offer));
    blobs.put(
        donor.actor(),
        new CloudEncryptedBlobs.Chunk(
            snapshotID, 1, 2, Arrays.copyOfRange(ciphertext, 262_144, ciphertext.length)));
    var tampered =
        new CloudSnapshots.Offer(
            requestID,
            snapshotID,
            donor.actor().deviceID(),
            1,
            cursor,
            ciphertext.length,
            2,
            "a".repeat(64),
            packetSignature,
            offer.signature());
    failCode("device_proof_invalid", () -> snapshots.publish(donor.actor(), tampered));
    snapshots.publish(donor.actor(), offer);
    snapshots.publish(donor.actor(), offer);
    assertEquals(digest, snapshots.status(receiver.actor(), requestID).offer().digest());
    assertTrue(snapshots.pending(donor.actor()).isEmpty());
    // A retention gap invalidates an older offer and asks a current donor again.
    clock.advance(Duration.ofDays(2));
    relay.upload(donor.actor(), packet(donor, UUID.randomUUID(), 2, 1));
    long newer = relay.pull(donor.actor(), cursor, 10).cursor();
    relay.acknowledge(donor.actor(), newer);
    db.transact(
        tx -> {
          tx.execute(
              "INSERT INTO relay_floor(workspace_id,sequence) VALUES (?,?)",
              donor.actor().workspaceID(),
              newer);
          return null;
        });
    assertNull(snapshots.status(receiver.actor(), requestID).offer());
    assertEquals(newer, snapshots.pending(donor.actor()).getFirst().minimumCursor());
    failCode("snapshot_cursor_unavailable", () -> snapshots.publish(donor.actor(), offer));
    clock.advance(Duration.ofDays(29));
    snapshots.purgeExpired();
    failCode("snapshot_request_unavailable", () -> snapshots.status(receiver.actor(), requestID));
  }

  @Test
  void leasesFenceProcessesAndRequireUnknownActionReconciliation() throws Exception {
    Device owner = bootstrap();
    var leases = new CloudLeases(db, clock, Duration.ofSeconds(90));
    UUID task = UUID.randomUUID(), child = UUID.randomUUID(), holder = UUID.randomUUID();
    leases.register(
        owner.actor(), new CloudLeases.Registration(task, owner.actor().deviceID(), null));
    leases.register(
        owner.actor(), new CloudLeases.Registration(child, owner.actor().deviceID(), task));
    var first = leases.acquire(owner.actor(), task, holder);
    assertEquals(1, first.generation());
    assertEquals(first, leases.acquire(owner.actor(), task, holder));
    failCode("lease_held", () -> leases.acquire(owner.actor(), task, UUID.randomUUID()));
    UUID action = UUID.randomUUID();
    String digest = "a".repeat(64);
    leases.beginAction(owner.actor(), task, holder, 1, action, digest);
    clock.advance(Duration.ofSeconds(91));
    failCode("lease_stale", () -> leases.check(owner.actor(), task, holder, 1));
    failCode("reconciliation_required", () -> leases.acquire(owner.actor(), task, holder));
    leases.finishAction(owner.actor(), task, action, digest, "UNKNOWN");
    failCode("reconciliation_required", () -> leases.acquire(owner.actor(), task, holder));
    leases.finishAction(owner.actor(), task, action, digest, "SUCCEEDED");
    assertEquals(2, leases.acquire(owner.actor(), task, holder).generation());
    failCode(
        "action_requires_reconciliation",
        () -> leases.beginAction(owner.actor(), task, holder, 2, action, digest));
    leases.cancel(owner.actor(), task);
    failCode("task_canceled", () -> leases.acquire(owner.actor(), child, holder));
  }

  @Test
  void revocationAtomicallyRotatesEpochAndBlocksOldDeviceAndCiphertext() throws Exception {
    Device owner = bootstrap(), phone = paired(owner);
    var leases = new CloudLeases(db, clock, Duration.ofSeconds(90));
    UUID task = UUID.randomUUID();
    leases.register(
        phone.actor(), new CloudLeases.Registration(task, phone.actor().deviceID(), null));
    leases.acquire(phone.actor(), task, UUID.randomUUID());
    var revocations = new CloudDeviceRevocations(db, tokens, json);
    Map<UUID, byte[]> grants = Map.of(owner.actor().deviceID(), new byte[64]);
    byte[] signature =
        sign(
            owner.keys(),
            CloudDeviceRevocations.message(
                owner.actor().workspaceID(),
                owner.actor().deviceID(),
                phone.actor().deviceID(),
                2,
                grants));
    var request =
        new CloudDeviceRevocations.Request(
            UUID.randomUUID(), phone.actor().deviceID(), 2, grants, signature);
    var result = revocations.revoke(owner.actor(), request);
    assertEquals(2, result.epoch());
    assertEquals(List.of(task), result.stoppedTasks());
    assertEquals(result, revocations.revoke(owner.actor(), request));
    failCode("device_revoked", () -> relay.pull(phone.actor(), 0, 10));
    failCode(
        "key_epoch_required",
        () -> relay.upload(owner.actor(), packet(owner, UUID.randomUUID(), 1, 1)));
    relay.upload(owner.actor(), packet(owner, UUID.randomUUID(), 1, 2));
    assertEquals(1, revocations.keys(owner.actor(), 1).size());
    assertFalse(
        new String(
                revocations.keys(owner.actor(), 1).getFirst().ciphertext(), StandardCharsets.UTF_8)
            .contains(PASSWORD));
  }

  @Test
  void quotaDoesNotDoubleChargeAndUnknownReservationsSurviveRestart() throws Exception {
    Device owner = bootstrap();
    var quota = new CloudModelQuota(db, clock, 1000);
    UUID id = UUID.randomUUID();
    quota.reserve(owner.actor(), id, 700);
    failCode("generation_already_started", () -> quota.reserve(owner.actor(), id, 700));
    failCode("model_quota_exceeded", () -> quota.reserve(owner.actor(), UUID.randomUUID(), 400));
    quota.settle(owner.actor(), id, 200L);
    quota.settle(owner.actor(), id, 200L);
    assertEquals(200, quota.usage(owner.actor()).used());
    UUID unknown = UUID.randomUUID();
    quota.reserve(owner.actor(), unknown, 600);
    quota.settle(owner.actor(), unknown, null);
    assertEquals(
        800,
        new CloudModelQuota(new CloudDatabase(directory.resolve("cloud.sqlite")), clock, 1000)
            .usage(owner.actor())
            .used());
    failCode("usage_conflict", () -> quota.settle(owner.actor(), id, 300L));
    clock.advance(Duration.ofDays(1));
    assertEquals(0, quota.usage(owner.actor()).used());
  }

  @Test
  void encryptedBlobChunksKeepTheirManifestAndExpire() throws Exception {
    Device owner = bootstrap();
    var blobs = new CloudEncryptedBlobs(db, tokens, clock);
    UUID blobID = UUID.randomUUID();
    byte[] ciphertext = new byte[80];
    new SecureRandom().nextBytes(ciphertext);
    var first = new CloudEncryptedBlobs.Chunk(blobID, 0, 2, ciphertext);
    blobs.put(owner.actor(), first);
    blobs.put(owner.actor(), first);
    assertArrayEquals(ciphertext, blobs.get(owner.actor(), blobID, 0).ciphertext());
    failCode(
        "blob_conflict",
        () -> blobs.put(owner.actor(), new CloudEncryptedBlobs.Chunk(blobID, 0, 3, ciphertext)));
    failCode(
        "blob_conflict",
        () -> blobs.put(owner.actor(), new CloudEncryptedBlobs.Chunk(blobID, 1, 3, ciphertext)));
    blobs.put(owner.actor(), new CloudEncryptedBlobs.Chunk(blobID, 1, 2, ciphertext));
    clock.advance(Duration.ofDays(31));
    failCode("blob_unavailable", () -> blobs.get(owner.actor(), blobID, 0));
    blobs.put(owner.actor(), first); // An available donor explicitly supplies the file again.
    assertArrayEquals(ciphertext, blobs.get(owner.actor(), blobID, 0).ciphertext());
    blobs.purgeExpired();
    clock.advance(Duration.ofDays(31));
    blobs.purgeExpired();
    long remaining =
        db.transact(
            tx -> tx.one("SELECT COUNT(*) FROM encrypted_blobs", r -> r.getLong(1)).orElseThrow());
    assertEquals(0L, remaining);
  }

  @Test
  void resetDoesNotRevealExistenceThroughCooldownOrSmtpFailure() throws Exception {
    bootstrap();
    var rates = new CloudRateLimiter(db, tokens, clock);
    var failedMail =
        new CloudEmailChallenges(
            db,
            tokens,
            (email, code, purpose) -> {
              throw new dev.blot.application.workspace.WorkspaceFailure(
                  503, "email_unavailable", "Unavailable");
            },
            rates,
            clock);
    var recovery = new CloudAccounts(db, new ArgonPasswordHasher(), failedMail, sessions, clock);
    assertDoesNotThrow(() -> recovery.requestReset(EMAIL));
    failCode("rate_limited", () -> recovery.requestReset(EMAIL));
    assertDoesNotThrow(() -> recovery.requestReset("missing@example.org"));
    failCode("rate_limited", () -> recovery.requestReset("missing@example.org"));
    failCode("code_expired_or_invalid", () -> recovery.reset(EMAIL, "bad", "a-new-valid-password"));
    failCode(
        "code_expired_or_invalid",
        () -> recovery.reset("missing@example.org", "bad", "a-new-valid-password"));
  }

  @Test
  void modelInvocationIsClaimedOnceAndLogoutStopsQueuedCalls() throws Exception {
    Device owner = bootstrap();
    var quota = new CloudModelQuota(db, clock, 1000);
    class Model implements ProviderGateway {
      int calls;
      boolean configured;

      public String concurrencyKey(UUID account) {
        if (!configured)
          throw new dev.blot.application.workspace.WorkspaceFailure(
              503, "provider_unconfigured", "Unavailable");
        return "component-test-provider";
      }

      public Reply generate(
          Request request,
          java.util.function.Consumer<String> text,
          java.util.function.BooleanSupplier canceled) {
        calls++;
        text.accept("Component result");
        return new Reply("Component result", List.of(), 3L, 4L);
      }

      public List<String> models(UUID account) {
        return List.of("GigaChat");
      }

      public long countTokens(UUID account, String model, String text) {
        return text.length();
      }
    }
    var provider = new Model();
    var gateway = new CloudModelGateway(provider, quota);
    var request =
        new CloudModelGateway.Completion(
            UUID.randomUUID(),
            "GigaChat",
            List.of(new CloudModelGateway.Message("user", "PRIVATE-COMPONENT-CONTEXT")),
            20);
    assertThrows(
        dev.blot.application.workspace.WorkspaceFailure.class,
        () -> gateway.prepare(owner.actor(), request));
    assertEquals(0, quota.usage(owner.actor()).used());
    provider.configured = true;
    var prepared = gateway.prepare(owner.actor(), request);
    assertEquals("Component result", gateway.generate(prepared, text -> {}, () -> false).text());
    assertEquals(7, quota.usage(owner.actor()).used());
    failCode(
        "generation_already_started", () -> gateway.generate(prepared, text -> {}, () -> false));
    failCode("generation_already_started", () -> gateway.prepare(owner.actor(), request));
    assertEquals(1, provider.calls);
    var queued =
        gateway.prepare(
            owner.actor(),
            new CloudModelGateway.Completion(
                UUID.randomUUID(), "GigaChat", request.messages(), 20));
    sessions.logout(owner.actor());
    failCode("session_expired", () -> gateway.generate(queued, text -> {}, () -> false));
    assertEquals(1, provider.calls);
    assertEquals(7, quota.usage(owner.actor()).used());
    for (Path file :
        List.of(directory.resolve("cloud.sqlite"), directory.resolve("cloud.sqlite-wal"))) {
      if (Files.exists(file))
        assertFalse(
            new String(Files.readAllBytes(file), StandardCharsets.ISO_8859_1)
                .contains("PRIVATE-COMPONENT-CONTEXT"));
    }
  }

  private Device bootstrap() throws Exception {
    accounts.register(EMAIL, PASSWORD, "Tester");
    var session = accounts.verify(EMAIL, mail.code);
    var actor = actor(session);
    KeyPair keys = key();
    UUID id = UUID.randomUUID();
    devices.bootstrap(actor, registration(actor, id, keys, "DESKTOP"));
    return new Device(sessions.require("Bearer " + session.accessToken(), true), keys);
  }

  private Device paired(Device owner) throws Exception {
    var invite = pairings.start(owner.actor());
    var session = accounts.login(EMAIL, PASSWORD);
    var actor = actor(session);
    KeyPair keys = key();
    UUID id = UUID.randomUUID();
    pairings.claim(actor, invite.id(), invite.secret(), claimRegistration(invite, id, keys));
    byte[] wrapped = new byte[64];
    byte[] signature =
        sign(
            owner.keys(),
            CloudPairings.approvalMessage(
                owner.actor().workspaceID(),
                invite.id(),
                owner.actor().deviceID(),
                id,
                1,
                raw(keys),
                raw(keys),
                wrapped));
    pairings.approve(
        owner.actor(), new CloudPairings.Approval(invite.id(), id, 1, wrapped, signature));
    return new Device(sessions.require("Bearer " + session.accessToken(), true), keys);
  }

  private CloudActor actor(CloudSessions.Tokens session) {
    return sessions.require("Bearer " + session.accessToken(), false);
  }

  private CloudDevices.Registration registration(
      CloudActor actor, UUID id, KeyPair key, String kind) throws Exception {
    return new CloudDevices.Registration(
        id,
        "Test device",
        kind,
        raw(key),
        raw(key),
        sign(
            key,
            CloudDeviceProof.message(
                "BLOT-DEVICE-BOOTSTRAP-1",
                List.of(actor.sessionID(), actor.workspaceID(), id),
                List.of(raw(key), raw(key)))));
  }

  private CloudDevices.Registration claimRegistration(
      CloudPairings.Invite invite, UUID id, KeyPair key) throws Exception {
    return new CloudDevices.Registration(
        id,
        "Test phone",
        "PHONE",
        raw(key),
        raw(key),
        sign(
            key,
            CloudDeviceProof.message(
                "BLOT-PAIR-CLAIM-1",
                List.of(invite.workspaceID(), invite.id(), id),
                List.of(raw(key), raw(key), invite.secret().getBytes(StandardCharsets.US_ASCII)))));
  }

  private CloudPacket packet(Device device, UUID id, long sequence, long epoch) throws Exception {
    byte[] ciphertext = new byte[80];
    new SecureRandom().nextBytes(ciphertext);
    var bytes = new ByteArrayOutputStream();
    var out = new DataOutputStream(bytes);
    out.write("BLOT-APPLE-SYNC-1".getBytes(StandardCharsets.US_ASCII));
    out.writeByte(1);
    for (UUID value : List.of(device.actor().workspaceID(), device.actor().deviceID(), id)) {
      out.writeLong(value.getMostSignificantBits());
      out.writeLong(value.getLeastSignificantBits());
    }
    out.writeLong(sequence);
    out.writeLong(epoch);
    out.write(ciphertext);
    return new CloudPacket(
        "change",
        device.actor().workspaceID(),
        device.actor().deviceID(),
        id,
        sequence,
        epoch,
        ciphertext,
        sign(device.keys(), bytes.toByteArray()));
  }

  private static KeyPair key() throws Exception {
    var generator = KeyPairGenerator.getInstance("EC");
    generator.initialize(new ECGenParameterSpec("secp256r1"));
    return generator.generateKeyPair();
  }

  private static byte[] sign(KeyPair key, byte[] message) throws Exception {
    var signature = Signature.getInstance("SHA256withECDSA");
    signature.initSign(key.getPrivate());
    signature.update(message);
    return signature.sign();
  }

  private static byte[] raw(KeyPair pair) {
    var key = (ECPublicKey) pair.getPublic();
    var result = new byte[65];
    result[0] = 4;
    coordinate(key.getW().getAffineX(), result, 1);
    coordinate(key.getW().getAffineY(), result, 33);
    return result;
  }

  private static void coordinate(BigInteger value, byte[] result, int start) {
    byte[] bytes = value.toByteArray();
    int length = Math.min(bytes.length, 32);
    System.arraycopy(bytes, bytes.length - length, result, start + 32 - length, length);
  }

  private static void failCode(String code, org.junit.jupiter.api.function.Executable action) {
    assertEquals(code, assertThrows(CloudFailure.class, action).code());
  }
}
