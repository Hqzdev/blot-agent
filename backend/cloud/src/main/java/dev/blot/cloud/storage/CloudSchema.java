package dev.blot.cloud.storage;

import dev.blot.cloud.CloudFailure;

final class CloudSchema {
  static void migrate(CloudTransaction tx) {
    int version = tx.one("PRAGMA user_version", r -> r.getInt(1)).orElse(0);
    if (version > 4) throw new CloudFailure(503, "schema_incompatible");
    if (version == 0)
      for (String sql :
          new String[] {
            "CREATE TABLE accounts (id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, name TEXT NOT NULL, verified INTEGER NOT NULL DEFAULT 0, bootstrap_used INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)",
            "CREATE TABLE workspaces (id TEXT PRIMARY KEY, owner_id TEXT UNIQUE NOT NULL REFERENCES accounts(id), epoch INTEGER NOT NULL DEFAULT 1)",
            "CREATE TABLE sessions (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES accounts(id), device_id TEXT, access_hash TEXT UNIQUE NOT NULL, refresh_hash TEXT UNIQUE NOT NULL, access_expires INTEGER NOT NULL, refresh_expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, bootstrap_allowed INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE email_challenges (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES accounts(id), purpose TEXT NOT NULL, code_hash TEXT NOT NULL, registration_hash TEXT, registration_name TEXT, expires INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)",
            "CREATE INDEX email_challenges_owner ON email_challenges(owner_id, purpose)",
            "CREATE TABLE binding_challenges (session_id TEXT PRIMARY KEY REFERENCES sessions(id), nonce_hash TEXT NOT NULL, expires INTEGER NOT NULL)",
            "CREATE TABLE auth_rates (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL)",
            "CREATE TABLE devices (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES accounts(id), workspace_id TEXT NOT NULL REFERENCES workspaces(id), name TEXT NOT NULL, kind TEXT NOT NULL, signing_key BLOB NOT NULL, encryption_key BLOB NOT NULL, certificate BLOB, revoked INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)",
            "CREATE TABLE pairings (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, workspace_id TEXT NOT NULL, initiator_id TEXT NOT NULL, secret_hash TEXT NOT NULL, expires INTEGER NOT NULL, candidate_id TEXT, candidate_signing BLOB, candidate_encryption BLOB, candidate_name TEXT, candidate_kind TEXT, claimant_session_id TEXT, approved INTEGER NOT NULL DEFAULT 0, approved_epoch INTEGER, wrapped_keys BLOB, approval_signature BLOB)",
            "CREATE TABLE device_key_grants (device_id TEXT NOT NULL REFERENCES devices(id), epoch INTEGER NOT NULL, ciphertext BLOB NOT NULL, signer_id TEXT NOT NULL, signature BLOB NOT NULL, PRIMARY KEY(device_id, epoch))",
            "CREATE TABLE relay_packets (delivery_seq INTEGER PRIMARY KEY AUTOINCREMENT, workspace_id TEXT NOT NULL REFERENCES workspaces(id), origin_device TEXT NOT NULL REFERENCES devices(id), change_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL, epoch INTEGER NOT NULL, packet TEXT NOT NULL, digest TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(workspace_id, origin_device, origin_sequence), UNIQUE(workspace_id, change_id))",
            "CREATE TABLE relay_receipts (change_id TEXT NOT NULL, workspace_id TEXT NOT NULL, origin_device TEXT NOT NULL, origin_sequence INTEGER NOT NULL, delivery_sequence INTEGER NOT NULL, digest TEXT NOT NULL, PRIMARY KEY(workspace_id, change_id), UNIQUE(workspace_id, origin_device, origin_sequence), UNIQUE(workspace_id, change_id))",
            "CREATE TABLE device_revocations (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, target_id TEXT NOT NULL, epoch INTEGER NOT NULL, digest TEXT NOT NULL)",
            "CREATE INDEX relay_workspace ON relay_packets(workspace_id, delivery_seq)",
            "CREATE TABLE relay_acks (workspace_id TEXT NOT NULL, device_id TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(workspace_id, device_id))",
            "CREATE TABLE relay_floor (workspace_id TEXT PRIMARY KEY, sequence INTEGER NOT NULL)",
            "CREATE TABLE task_assignments (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, executor_device TEXT NOT NULL, parent_id TEXT, canceled INTEGER NOT NULL DEFAULT 0, generation INTEGER NOT NULL DEFAULT 0, lease_expires INTEGER, holder_id TEXT)",
            "CREATE TABLE external_actions (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, device_id TEXT NOT NULL, digest TEXT NOT NULL, state TEXT NOT NULL)",
            "CREATE TABLE encrypted_blobs (workspace_id TEXT NOT NULL, blob_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk_count INTEGER NOT NULL, creator_id TEXT NOT NULL, ciphertext BLOB NOT NULL, digest TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(workspace_id, blob_id, chunk_index))",
            "CREATE TABLE model_usage (owner_id TEXT NOT NULL, request_id TEXT PRIMARY KEY, reserved INTEGER NOT NULL, actual INTEGER, state TEXT NOT NULL, created_at INTEGER NOT NULL)",
            "PRAGMA user_version = 1"
          }) tx.execute(sql);
    if (version < 2) {
      tx.execute(
          "CREATE TABLE snapshot_requests (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES workspaces(id), requester_id TEXT NOT NULL REFERENCES devices(id), minimum_cursor INTEGER NOT NULL, expires INTEGER NOT NULL, offer TEXT, donor_id TEXT, offer_epoch INTEGER, offer_cursor INTEGER)");
      tx.execute(
          "CREATE INDEX snapshot_requests_workspace ON snapshot_requests(workspace_id, expires)");
      tx.execute("PRAGMA user_version = 2");
    }
    if (version < 3) {
      tx.execute(
          "CREATE TABLE browser_authorizations (code_hash TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id), owner_id TEXT NOT NULL REFERENCES accounts(id), client_id TEXT NOT NULL, redirect_uri TEXT NOT NULL, challenge TEXT NOT NULL, expires INTEGER NOT NULL, bootstrap_allowed INTEGER NOT NULL)");
      tx.execute("CREATE INDEX browser_authorizations_expiry ON browser_authorizations(expires)");
      tx.execute("PRAGMA user_version = 3");
    }
    if (version < 4) {
      tx.execute("ALTER TABLE accounts ADD COLUMN google_subject TEXT");
      tx.execute("CREATE UNIQUE INDEX accounts_google_subject ON accounts(google_subject)");
      tx.execute("PRAGMA user_version = 4");
    }
  }
}
