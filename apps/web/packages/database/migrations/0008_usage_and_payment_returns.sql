CREATE TABLE billing.usage_windows (
  user_id uuid NOT NULL, hours integer NOT NULL CHECK (hours IN (5,168)),
  starts_at timestamptz NOT NULL, used bigint NOT NULL DEFAULT 0 CHECK (used >= 0),
  PRIMARY KEY (user_id,hours)
);
CREATE TABLE billing.usage_reservations (
  id uuid PRIMARY KEY, user_id uuid NOT NULL, short_start timestamptz NOT NULL,
  week_start timestamptz NOT NULL, amount bigint NOT NULL CHECK (amount >= 0)
);
CREATE TABLE billing.payment_returns (
  id uuid PRIMARY KEY, user_id uuid NOT NULL, device_challenge text NOT NULL,
  payment_id uuid UNIQUE REFERENCES billing.payments(id), code_hash text UNIQUE,
  expires_at timestamptz NOT NULL, code_expires_at timestamptz
);
CREATE TABLE billing.quota_pilots (
  invitation_digest text PRIMARY KEY, user_id uuid NOT NULL UNIQUE
);
