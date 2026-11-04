package dev.blot.cloud.execution;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.storage.*;
import java.time.*;
import java.util.*;

public final class CloudLeases {
  public record Registration(UUID taskID, UUID executorDeviceID, UUID parentTaskID) {}

  public record Lease(
      UUID taskID, UUID executorDeviceID, UUID holderID, long generation, String expiresAt) {}

  private record Assignment(
      UUID id,
      UUID device,
      UUID parent,
      boolean canceled,
      long generation,
      Long expires,
      UUID holder) {}

  private final CloudDatabase database;
  private final Clock clock;
  private final Duration duration;

  public CloudLeases(CloudDatabase database, Clock clock, Duration duration) {
    this.database = database;
    this.clock = clock;
    this.duration = duration;
  }

  public void register(CloudActor actor, Registration registration) {
    if (registration == null
        || registration.taskID() == null
        || registration.executorDeviceID() == null) throw new CloudFailure(400, "invalid_task");
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          if (tx.one(
                  "SELECT id FROM devices WHERE id = ? AND workspace_id = ? AND revoked = 0",
                  r -> r.getString(1),
                  registration.executorDeviceID(),
                  actor.workspaceID())
              .isEmpty()) throw new CloudFailure(403, "executor_unavailable");
          var old = find(tx, actor.workspaceID(), registration.taskID());
          if (old.isPresent()) {
            if (!old.get().device().equals(registration.executorDeviceID())
                || !Objects.equals(old.get().parent(), registration.parentTaskID()))
              throw new CloudFailure(409, "command_conflict");
            return null;
          }
          UUID parent = registration.parentTaskID();
          int depth = 0;
          while (parent != null) {
            depth++;
            if (depth > 2 || parent.equals(registration.taskID()))
              throw new CloudFailure(403, "delegation_depth");
            Assignment ancestor = require(tx, actor.workspaceID(), parent);
            if (ancestor.canceled() || !ancestor.device().equals(registration.executorDeviceID()))
              throw new CloudFailure(403, "task_canceled");
            parent = ancestor.parent();
          }
          tx.execute(
              "INSERT INTO task_assignments(id, workspace_id, executor_device, parent_id) VALUES (?, ?, ?, ?)",
              registration.taskID(),
              actor.workspaceID(),
              registration.executorDeviceID(),
              registration.parentTaskID());
          return null;
        });
  }

  public Lease acquire(CloudActor actor, UUID taskID, UUID holderID) {
    if (holderID == null) throw new CloudFailure(400, "invalid_holder");
    return database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          Assignment task = require(tx, actor.workspaceID(), taskID);
          validateOwner(actor, task);
          if (task.expires() != null && task.expires() > clock.millis()) {
            if (!holderID.equals(task.holder())) throw new CloudFailure(409, "lease_held");
            return view(task);
          }
          if (tx.one(
                  "SELECT id FROM external_actions WHERE task_id = ? AND state IN ('RUNNING','UNKNOWN') LIMIT 1",
                  r -> r.getString(1),
                  taskID)
              .isPresent()) throw new CloudFailure(409, "reconciliation_required");
          long active =
              tx.one(
                      "SELECT COUNT(*) FROM task_assignments WHERE workspace_id = ? AND canceled = 0 AND lease_expires > ?",
                      r -> r.getLong(1),
                      actor.workspaceID(),
                      clock.instant())
                  .orElse(0L);
          if (active >= 4 || task.generation() == Long.MAX_VALUE)
            throw new CloudFailure(429, "executor_limit");
          tx.execute(
              "UPDATE task_assignments SET generation = generation + 1, lease_expires = ?, holder_id = ? WHERE id = ?",
              clock.instant().plus(duration),
              holderID,
              taskID);
          return view(require(tx, actor.workspaceID(), taskID));
        });
  }

  public Lease renew(CloudActor actor, UUID taskID, UUID holderID, long generation) {
    return database.transact(
        tx -> {
          validate(tx, actor, taskID, holderID, generation);
          tx.execute(
              "UPDATE task_assignments SET lease_expires = ? WHERE id = ?",
              clock.instant().plus(duration),
              taskID);
          return view(require(tx, actor.workspaceID(), taskID));
        });
  }

  public void check(CloudActor actor, UUID taskID, UUID holderID, long generation) {
    database.transact(
        tx -> {
          validate(tx, actor, taskID, holderID, generation);
          return null;
        });
  }

  public void release(CloudActor actor, UUID taskID, UUID holderID, long generation) {
    database.transact(
        tx -> {
          validate(tx, actor, taskID, holderID, generation);
          tx.execute(
              "UPDATE task_assignments SET lease_expires = NULL, holder_id = NULL WHERE id = ?",
              taskID);
          return null;
        });
  }

  public void cancel(CloudActor actor, UUID taskID) {
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          require(tx, actor.workspaceID(), taskID);
          tx.execute(
              "WITH RECURSIVE family(id) AS (SELECT id FROM task_assignments WHERE id = ? AND workspace_id = ? UNION ALL SELECT t.id FROM task_assignments t JOIN family p ON t.parent_id = p.id) UPDATE task_assignments SET canceled = 1, lease_expires = NULL, holder_id = NULL WHERE id IN (SELECT id FROM family)",
              taskID,
              actor.workspaceID());
          return null;
        });
  }

  public void beginAction(
      CloudActor actor, UUID taskID, UUID holderID, long generation, UUID actionID, String digest) {
    if (actionID == null || digest == null || !digest.matches("[0-9a-f]{64}"))
      throw new CloudFailure(400, "invalid_action");
    database.transact(
        tx -> {
          validate(tx, actor, taskID, holderID, generation);
          if (tx.one("SELECT id FROM external_actions WHERE id = ?", r -> r.getString(1), actionID)
              .isPresent()) throw new CloudFailure(409, "action_requires_reconciliation");
          tx.execute(
              "INSERT INTO external_actions(id, task_id, device_id, digest, state) VALUES (?, ?, ?, ?, 'RUNNING')",
              actionID,
              taskID,
              actor.deviceID(),
              digest);
          return null;
        });
  }

  public void finishAction(
      CloudActor actor, UUID taskID, UUID actionID, String digest, String state) {
    if (state == null || !Set.of("SUCCEEDED", "FAILED", "UNKNOWN").contains(state))
      throw new CloudFailure(400, "invalid_action_state");
    database.transact(
        tx -> {
          CloudDevices.requireActive(tx, actor);
          Assignment task = require(tx, actor.workspaceID(), taskID);
          if (!task.device().equals(actor.deviceID()))
            throw new CloudFailure(403, "executor_denied");
          var old =
              tx.one(
                      "SELECT digest, state FROM external_actions WHERE id = ? AND task_id = ? AND device_id = ?",
                      r -> new String[] {r.getString(1), r.getString(2)},
                      actionID,
                      taskID,
                      actor.deviceID())
                  .orElseThrow(() -> new CloudFailure(404, "action_not_found"));
          if (!old[0].equals(digest)
              || (!Set.of("RUNNING", "UNKNOWN").contains(old[1]) && !old[1].equals(state)))
            throw new CloudFailure(409, "action_conflict");
          tx.execute("UPDATE external_actions SET state = ? WHERE id = ?", state, actionID);
          return null;
        });
  }

  private void validate(
      CloudTransaction tx, CloudActor actor, UUID taskID, UUID holderID, long generation) {
    CloudDevices.requireActive(tx, actor);
    Assignment task = require(tx, actor.workspaceID(), taskID);
    validateOwner(actor, task);
    if (!Objects.equals(task.holder(), holderID)
        || task.generation() != generation
        || task.expires() == null
        || task.expires() <= clock.millis()) throw new CloudFailure(409, "lease_stale");
  }

  private void validateOwner(CloudActor actor, Assignment task) {
    if (task.canceled()) throw new CloudFailure(409, "task_canceled");
    if (!task.device().equals(actor.deviceID())) throw new CloudFailure(403, "executor_denied");
  }

  private Lease view(Assignment value) {
    return new Lease(
        value.id(),
        value.device(),
        value.holder(),
        value.generation(),
        Instant.ofEpochMilli(Objects.requireNonNull(value.expires())).toString());
  }

  private Assignment require(CloudTransaction tx, UUID workspace, UUID id) {
    return find(tx, workspace, id).orElseThrow(() -> new CloudFailure(404, "task_not_found"));
  }

  private Optional<Assignment> find(CloudTransaction tx, UUID workspace, UUID id) {
    return tx.one(
        "SELECT id, executor_device, parent_id, canceled, generation, lease_expires, holder_id FROM task_assignments WHERE id = ? AND workspace_id = ?",
        r ->
            new Assignment(
                UUID.fromString(r.getString(1)),
                UUID.fromString(r.getString(2)),
                uuid(r.getString(3)),
                r.getInt(4) != 0,
                r.getLong(5),
                r.getObject(6) == null ? null : r.getLong(6),
                uuid(r.getString(7))),
        id,
        workspace);
  }

  private UUID uuid(String value) {
    return value == null ? null : UUID.fromString(value);
  }
}
