package dev.blot.application.workspace.identity;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.identity.AuthSessionData;
import dev.blot.core.workspace.identity.DeviceData;
import dev.blot.core.workspace.identity.PairingData;
import java.time.*;
import java.util.*;

public final class DeviceService {
  public record PairingTicket(UUID id, String secret, Instant expiresAt) {}

  private final java.util.Map<UUID, String> ticketSecrets =
      new java.util.concurrent.ConcurrentHashMap<>();
  private final java.util.Map<UUID, SessionService.SessionToken> claimedTokens =
      new java.util.concurrent.ConcurrentHashMap<>();
  private final WorkspaceStore store;
  private final Records records;
  private final Clock clock;
  private final TokenGenerator tokens;
  private final SessionService sessions;

  public DeviceService(
      WorkspaceStore store,
      Records records,
      Clock clock,
      TokenGenerator tokens,
      SessionService sessions) {
    this.store = store;
    this.records = records;
    this.clock = clock;
    this.tokens = tokens;
    this.sessions = sessions;
  }

  public PairingTicket create(WorkspaceStore.Transaction tx, Actor actor) {
    local(actor);
    String secret = tokens.token();
    Instant until = clock.instant().plusSeconds(300);
    var e =
        records.create(
            tx,
            EntityKind.PAIRING,
            actor.accountId(),
            null,
            null,
            new PairingData(tokens.digest(secret), until, null, null, null, false, false));
    ticketSecrets.put(e.id(), secret);
    return new PairingTicket(e.id(), null, until);
  }

  public PairingTicket ticket(Actor actor, UUID id) {
    local(actor);
    var e =
        store.transact(
            tx ->
                Records.require(tx, EntityKind.PAIRING, actor.accountId(), id, PairingData.class));
    if (e.data().expiresAt().isBefore(clock.instant()) || e.data().claimed())
      throw WorkspaceFailure.missing();
    String secret = ticketSecrets.get(id);
    if (secret == null) throw new WorkspaceFailure(409, "pairing_expired", "Создайте новый QR-код");
    return new PairingTicket(id, secret, e.data().expiresAt());
  }

  public UUID request(UUID id, String secret, String name, String platform) {
    return store.transact(
        tx -> {
          var e = find(tx, id, secret);
          var d = e.data();
          if (d.deviceId() != null) {
            if (Objects.equals(name, d.deviceName()) && Objects.equals(platform, d.platform()))
              return d.deviceId();
            throw WorkspaceFailure.invalid("Устройство уже запросило сопряжение");
          }
          var device =
              records.create(
                  tx,
                  EntityKind.DEVICE,
                  e.ownerId(),
                  null,
                  null,
                  new DeviceData(
                      Records.text(name, "name", 100),
                      Records.text(platform, "platform", 50),
                      true));
          records.change(
              tx,
              EntityKind.PAIRING,
              e,
              new PairingData(
                  d.secretHash(), d.expiresAt(), name, platform, device.id(), false, false));
          return device.id();
        });
  }

  public Entity<PairingData> approve(
      WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    local(actor);
    var e = Records.require(tx, EntityKind.PAIRING, actor.accountId(), id, PairingData.class);
    Records.version(e, version);
    var d = e.data();
    if (d.deviceId() == null || d.claimed() || d.expiresAt().isBefore(clock.instant()))
      throw WorkspaceFailure.invalid("Сопряжение истекло");
    var device =
        Records.require(tx, EntityKind.DEVICE, actor.accountId(), d.deviceId(), DeviceData.class);
    records.change(
        tx, EntityKind.DEVICE, device, new DeviceData(d.deviceName(), d.platform(), false));
    return records.change(
        tx,
        EntityKind.PAIRING,
        e,
        new PairingData(
            d.secretHash(),
            d.expiresAt(),
            d.deviceName(),
            d.platform(),
            d.deviceId(),
            true,
            false));
  }

  public synchronized SessionService.SessionToken claim(UUID id, String secret) {
    if (claimedTokens.containsKey(id)) {
      store.transact(tx -> find(tx, id, secret));
      return claimedTokens.get(id);
    }
    var e =
        store.transact(
            tx -> {
              var found = find(tx, id, secret);
              var d = found.data();
              if (!d.approved() || d.claimed())
                throw new WorkspaceFailure(409, "pairing_pending", "Подтвердите устройство на Mac");
              records.change(
                  tx,
                  EntityKind.PAIRING,
                  found,
                  new PairingData(
                      d.secretHash(),
                      d.expiresAt(),
                      d.deviceName(),
                      d.platform(),
                      d.deviceId(),
                      true,
                      true));
              return found;
            });
    var token = sessions.create(e.ownerId(), e.data().deviceId(), true);
    claimedTokens.put(id, token);
    ticketSecrets.remove(id);
    return token;
  }

  public void revoke(WorkspaceStore.Transaction tx, Actor actor, UUID id) {
    var e = Records.require(tx, EntityKind.DEVICE, actor.accountId(), id, DeviceData.class);
    records.change(
        tx, EntityKind.DEVICE, e, new DeviceData(e.data().name(), e.data().platform(), true));
    for (var s :
        tx.list(
            EntityKind.AUTH_SESSION, actor.accountId(), null, null, AuthSessionData.class, 10000))
      if (id.equals(s.data().deviceId()))
        tx.delete(EntityKind.AUTH_SESSION, actor.accountId(), s.id());
  }

  private Entity<PairingData> find(WorkspaceStore.Transaction tx, UUID id, String secret) {
    return tx.scan(EntityKind.PAIRING, PairingData.class, 10000).stream()
        .filter(
            e ->
                e.id().equals(id)
                    && tokens.matches(secret, e.data().secretHash())
                    && e.data().expiresAt().isAfter(clock.instant()))
        .findFirst()
        .orElseThrow(WorkspaceFailure::missing);
  }

  private static void local(Actor a) {
    if (!a.local() || a.deviceId() != null)
      throw new WorkspaceFailure(403, "local_required", "Действие доступно только на Mac");
  }
}
