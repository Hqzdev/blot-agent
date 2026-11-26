CREATE TABLE "identity"."blot_profiles" (
  "owner_id" uuid PRIMARY KEY NOT NULL,
  "nickname" varchar(80),
  "customization" jsonb,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
