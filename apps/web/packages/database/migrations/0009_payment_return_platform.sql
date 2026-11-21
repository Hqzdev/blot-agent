ALTER TABLE billing.payment_returns
  ADD COLUMN platform text NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'macos'));
