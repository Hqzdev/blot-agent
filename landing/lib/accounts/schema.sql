CREATE TABLE IF NOT EXISTS blot_accounts (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL UNIQUE,
  email text NOT NULL UNIQUE,
  name text NOT NULL,
  password_hash text,
  google_subject text UNIQUE,
  verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE blot_accounts ADD COLUMN IF NOT EXISTS yandex_subject text;
CREATE UNIQUE INDEX IF NOT EXISTS blot_accounts_yandex_subject ON blot_accounts(yandex_subject);
ALTER TABLE blot_accounts ADD COLUMN IF NOT EXISTS avatar_url text;
CREATE TABLE IF NOT EXISTS blot_sessions (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES blot_accounts(id) ON DELETE CASCADE,
  access_hash text NOT NULL UNIQUE,
  refresh_hash text NOT NULL UNIQUE,
  access_expires timestamptz NOT NULL,
  refresh_expires timestamptz NOT NULL,
  revoked boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS blot_sessions_owner ON blot_sessions(owner_id);
CREATE TABLE IF NOT EXISTS blot_email_challenges (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES blot_accounts(id) ON DELETE CASCADE,
  purpose text NOT NULL CHECK (purpose IN ('verify', 'reset', 'delete', 'signin')),
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  registration_hash text,
  registration_name text,
  UNIQUE(owner_id, purpose)
);
CREATE TABLE IF NOT EXISTS blot_auth_rates (
  key text PRIMARY KEY,
  count integer NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS blot_browser_codes (
  code_hash text PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES blot_sessions(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES blot_accounts(id) ON DELETE CASCADE,
  client_id text NOT NULL,
  redirect_uri text NOT NULL,
  challenge text NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS blot_workspace_backups (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES blot_accounts(id) ON DELETE CASCADE,
  device_id uuid NOT NULL,
  digest text NOT NULL,
  byte_count integer NOT NULL CHECK (byte_count BETWEEN 1 AND 33554432),
  chunk_count integer NOT NULL CHECK (chunk_count BETWEEN 1 AND 64),
  committed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS blot_backups_owner ON blot_workspace_backups(owner_id, device_id);
CREATE TABLE IF NOT EXISTS blot_workspace_backup_parts (
  snapshot_id uuid NOT NULL REFERENCES blot_workspace_backups(id) ON DELETE CASCADE,
  part integer NOT NULL CHECK (part BETWEEN 0 AND 63),
  payload bytea NOT NULL CHECK (octet_length(payload) BETWEEN 1 AND 524288),
  PRIMARY KEY(snapshot_id, part)
);

ALTER TABLE blot_email_challenges DROP CONSTRAINT IF EXISTS blot_email_challenges_purpose_check;
ALTER TABLE blot_email_challenges ADD CONSTRAINT blot_email_challenges_purpose_check CHECK (purpose IN ('verify', 'reset', 'delete', 'signin'));
