package dev.blot.cloud.identity;

import dev.blot.cloud.storage.CloudTransaction;

/** Removes the owner's whole cloud graph in the existing confirmation transaction. */
final class CloudAccountRemoval {
  static void remove(CloudTransaction tx, CloudActor actor) {
    var owner = actor.ownerID();
    var workspace =
        tx.one(
                "SELECT id FROM workspaces WHERE owner_id = ?",
                r -> java.util.UUID.fromString(r.getString(1)),
                owner)
            .orElseThrow(() -> new dev.blot.cloud.CloudFailure(401, "session_expired"));
    if (!workspace.equals(actor.workspaceID()))
      throw new dev.blot.cloud.CloudFailure(403, "workspace_denied");
    tx.execute(
        "DELETE FROM external_actions WHERE task_id IN (SELECT id FROM task_assignments WHERE"
            + " workspace_id = ?)",
        workspace);
    tx.execute("DELETE FROM task_assignments WHERE workspace_id = ?", workspace);
    for (String table :
        new String[] {
          "snapshot_requests",
          "relay_packets",
          "relay_receipts",
          "relay_acks",
          "relay_floor",
          "device_revocations",
          "encrypted_blobs"
        }) {
      tx.execute("DELETE FROM " + table + " WHERE workspace_id = ?", workspace);
    }
    tx.execute(
        "DELETE FROM device_key_grants WHERE device_id IN (SELECT id FROM devices WHERE"
            + " workspace_id = ?)",
        workspace);
    tx.execute("DELETE FROM pairings WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM devices WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM browser_authorizations WHERE owner_id = ?", owner);
    tx.execute(
        "DELETE FROM binding_challenges WHERE session_id IN (SELECT id FROM sessions WHERE owner_id"
            + " = ?)",
        owner);
    tx.execute("DELETE FROM sessions WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM model_usage WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM email_challenges WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM workspaces WHERE owner_id = ?", owner);
    tx.execute("DELETE FROM accounts WHERE id = ?", owner);
  }
}
