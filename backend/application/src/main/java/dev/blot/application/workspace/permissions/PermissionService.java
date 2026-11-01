package dev.blot.application.workspace.permissions;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.execution.PreparedActionData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.identity.GrantData;
import java.time.*;
import java.util.*;

public final class PermissionService {
  private final Records records;
  private final JsonCodec json;
  private final TokenGenerator tokens;
  private final Clock clock;

  public PermissionService(Records records, JsonCodec json, TokenGenerator tokens, Clock clock) {
    this.records = records;
    this.json = json;
    this.tokens = tokens;
    this.clock = clock;
  }

  public Entity<PreparedActionData> prepare(
      WorkspaceStore.Transaction tx,
      UUID owner,
      UUID project,
      UUID session,
      UUID task,
      String capability,
      String base,
      Map<String, Object> args) {
    String hash =
        tokens.digest(
            json.write(
                Map.of(
                    "capability",
                    capability,
                    "session",
                    session,
                    "base",
                    base,
                    "arguments",
                    args)));
    var existing =
        tx
            .all(EntityKind.PREPARED_ACTION, owner, project, session, PreparedActionData.class)
            .stream()
            .filter(e -> e.data().hash().equals(hash))
            .findFirst();
    if (existing.isPresent()) return existing.get();
    return records.create(
        tx,
        EntityKind.PREPARED_ACTION,
        owner,
        project,
        session,
        new PreparedActionData(
            capability, session, task, base, Map.copyOf(args), hash, "PREPARED"));
  }

  public Entity<GrantData> grant(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID action,
      Long version,
      int seconds,
      int uses) {
    var e =
        Records.require(
            tx, EntityKind.PREPARED_ACTION, actor.accountId(), action, PreparedActionData.class);
    Records.version(e, version);
    if (!e.data().status().equals("PREPARED") || seconds < 1 || seconds > 86400 || uses != 1)
      throw WorkspaceFailure.invalid("Неверное разрешение");
    // Подтверждение на Mac и телефоне конкурирует за одну версию подготовленного действия.
    records.change(tx, EntityKind.PREPARED_ACTION, e, e.data());
    return records.create(
        tx,
        EntityKind.GRANT,
        actor.accountId(),
        e.projectId(),
        action,
        new GrantData(
            action,
            e.data().hash(),
            clock.instant().plusSeconds(seconds),
            uses,
            actor.accountId(),
            false));
  }

  public void consume(
      WorkspaceStore.Transaction tx, UUID owner, Entity<PreparedActionData> action) {
    var grant =
        tx.list(EntityKind.GRANT, owner, null, action.id(), GrantData.class, 10000).stream()
            .filter(
                e ->
                    !e.data().revoked()
                        && e.data().usesRemaining() > 0
                        && e.data().expiresAt().isAfter(clock.instant())
                        && e.data().actionHash().equals(action.data().hash()))
            .findFirst()
            .orElseThrow(
                () ->
                    new WorkspaceFailure(
                            403, "permission_required", "Подтвердите подготовленное действие")
                        .forResource(action.id()));
    var d = grant.data();
    records.change(
        tx,
        EntityKind.GRANT,
        grant,
        new GrantData(
            d.preparedActionId(),
            d.actionHash(),
            d.expiresAt(),
            d.usesRemaining() - 1,
            d.grantedBy(),
            false));
  }

  public boolean executionAllowed(
      WorkspaceStore.Transaction tx, UUID owner, Entity<PreparedActionData> action) {
    return tx.list(EntityKind.GRANT, owner, null, action.id(), GrantData.class, 10000).stream()
        .anyMatch(
            g ->
                !g.data().revoked()
                    && g.data().expiresAt().isAfter(clock.instant())
                    && g.data().actionHash().equals(action.data().hash()));
  }

  public void revoke(WorkspaceStore.Transaction tx, Actor actor, UUID id, Long version) {
    var e = Records.require(tx, EntityKind.GRANT, actor.accountId(), id, GrantData.class);
    Records.version(e, version);
    var d = e.data();
    records.change(
        tx,
        EntityKind.GRANT,
        e,
        new GrantData(d.preparedActionId(), d.actionHash(), d.expiresAt(), 0, d.grantedBy(), true));
  }
}
