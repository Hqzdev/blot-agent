-- Existing payment history remains live/legacy. New checkouts are test-only.
ALTER TABLE billing.payments ADD COLUMN test boolean NOT NULL DEFAULT false;
ALTER TABLE billing.payments ALTER COLUMN test SET DEFAULT true;
CREATE TABLE billing.test_subscriptions (
  user_id uuid PRIMARY KEY,
  plan varchar(24) NOT NULL CHECK (plan IN ('premium', 'super', 'ultra')),
  source_payment_id uuid NOT NULL,
  valid_until timestamptz NOT NULL
);
ALTER TABLE billing.payments DROP CONSTRAINT IF EXISTS payments_plan_check;
ALTER TABLE billing.payments ADD CONSTRAINT payments_plan_check CHECK (plan IN ('premium', 'super', 'ultra', 'team'));
ALTER TABLE billing.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_plan_check;
ALTER TABLE billing.subscriptions ADD CONSTRAINT subscriptions_plan_check CHECK (plan IN ('free', 'premium', 'super', 'ultra', 'team'));
UPDATE billing.plans SET active = false WHERE id = 'team';
INSERT INTO billing.plans(id, name, amount_minor, currency, active) VALUES
  ('premium', 'Premium', 250000, 'RUB', true),
  ('super', 'Super', 500000, 'RUB', true),
  ('ultra', 'Ultra', 1000000, 'RUB', true)
ON CONFLICT (id) DO UPDATE SET name = excluded.name, amount_minor = excluded.amount_minor, currency = excluded.currency, active = true;

ALTER TABLE billing.payments ADD COLUMN card_id uuid;
CREATE INDEX payments_card_owner_idx ON billing.payments(user_id, card_id, created_at DESC);
