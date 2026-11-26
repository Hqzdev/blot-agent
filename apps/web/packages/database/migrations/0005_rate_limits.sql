CREATE TABLE "blot_web"."rate_limits" (
  "key" varchar(256) PRIMARY KEY NOT NULL,
  "count" integer NOT NULL,
  "resets_at" timestamptz NOT NULL
);
CREATE INDEX "rate_limits_expiry_idx" ON "blot_web"."rate_limits" ("resets_at");
