CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS "identity";
CREATE SCHEMA IF NOT EXISTS "conversation";
CREATE SCHEMA IF NOT EXISTS "billing";
CREATE SCHEMA IF NOT EXISTS "ai";

CREATE TABLE "identity"."users" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "email" varchar(320) NOT NULL,
  "password_hash" varchar(255),
  "nickname" varchar(32) NOT NULL,
  "customization" jsonb,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX "users_email_unique" ON "identity"."users" ("email");
CREATE UNIQUE INDEX "users_nickname_unique" ON "identity"."users" ("nickname");

CREATE TABLE "conversation"."chats" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "title" text NOT NULL,
  "visibility" varchar(16) DEFAULT 'private' NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "chats_visibility_check" CHECK ("visibility" IN ('private', 'public'))
);

CREATE INDEX "chats_user_created_at_idx" ON "conversation"."chats" ("user_id", "created_at");

CREATE TABLE "conversation"."messages" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "chat_id" uuid NOT NULL REFERENCES "conversation"."chats"("id") ON DELETE CASCADE,
  "role" varchar(32) NOT NULL,
  "parts" jsonb NOT NULL,
  "attachments" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE INDEX "messages_chat_created_at_idx" ON "conversation"."messages" ("chat_id", "created_at");

CREATE TABLE "conversation"."votes" (
  "chat_id" uuid NOT NULL REFERENCES "conversation"."chats"("id") ON DELETE CASCADE,
  "message_id" uuid NOT NULL REFERENCES "conversation"."messages"("id") ON DELETE CASCADE,
  "is_upvoted" boolean NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "votes_pk" PRIMARY KEY ("chat_id", "message_id")
);

CREATE TABLE "conversation"."documents" (
  "id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "user_id" uuid NOT NULL,
  "title" text NOT NULL,
  "content" text,
  "kind" varchar(16) DEFAULT 'text' NOT NULL,
  CONSTRAINT "documents_pk" PRIMARY KEY ("id", "created_at"),
  CONSTRAINT "documents_kind_check" CHECK ("kind" IN ('text', 'code', 'image', 'sheet'))
);

CREATE INDEX "documents_user_created_at_idx" ON "conversation"."documents" ("user_id", "created_at");

CREATE TABLE "conversation"."suggestions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "document_id" uuid NOT NULL,
  "document_created_at" timestamp with time zone NOT NULL,
  "original_text" text NOT NULL,
  "suggested_text" text NOT NULL,
  "description" text,
  "is_resolved" boolean DEFAULT false NOT NULL,
  "user_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "suggestions_document_fk" FOREIGN KEY ("document_id", "document_created_at") REFERENCES "conversation"."documents"("id", "created_at") ON DELETE CASCADE
);

CREATE INDEX "suggestions_document_idx" ON "conversation"."suggestions" ("document_id", "document_created_at");

CREATE TABLE "conversation"."object_files" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "pathname" text NOT NULL,
  "url" text NOT NULL,
  "content_type" varchar(255) NOT NULL,
  "size" bigint NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE INDEX "object_files_user_created_at_idx" ON "conversation"."object_files" ("user_id", "created_at");

CREATE TABLE "billing"."plans" (
  "id" varchar(24) PRIMARY KEY NOT NULL,
  "name" varchar(80) NOT NULL,
  "amount_minor" integer NOT NULL,
  "currency" varchar(3) DEFAULT 'RUB' NOT NULL,
  "active" boolean DEFAULT true NOT NULL,
  CONSTRAINT "plans_amount_check" CHECK ("amount_minor" >= 0)
);

INSERT INTO "billing"."plans" ("id", "name", "amount_minor", "currency", "active")
VALUES
  ('free', 'Free', 0, 'RUB', true),
  ('premium', 'Premium', 150000, 'RUB', true),
  ('team', 'Team', 200000, 'RUB', true);

CREATE TABLE "billing"."subscriptions" (
  "user_id" uuid PRIMARY KEY NOT NULL,
  "plan" varchar(24) DEFAULT 'free' NOT NULL,
  "status" varchar(24) DEFAULT 'active' NOT NULL,
  "source_payment_id" uuid,
  "valid_until" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "subscriptions_plan_check" CHECK ("plan" IN ('free', 'premium', 'team'))
);

CREATE TABLE "billing"."payments" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "provider_payment_id" varchar(128),
  "idempotency_key" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  "plan" varchar(24) NOT NULL,
  "amount_minor" integer NOT NULL,
  "currency" varchar(3) DEFAULT 'RUB' NOT NULL,
  "status" varchar(32) DEFAULT 'pending' NOT NULL,
  "confirmation_url" text,
  "provider_payload" jsonb,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "payments_plan_check" CHECK ("plan" IN ('premium', 'team')),
  CONSTRAINT "payments_amount_check" CHECK ("amount_minor" > 0)
);

CREATE UNIQUE INDEX "payments_idempotency_key_unique" ON "billing"."payments" ("idempotency_key");
CREATE UNIQUE INDEX "payments_provider_payment_id_unique" ON "billing"."payments" ("provider_payment_id");
CREATE INDEX "payments_user_created_at_idx" ON "billing"."payments" ("user_id", "created_at");

CREATE TABLE "billing"."webhook_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "event_key" varchar(180) UNIQUE NOT NULL,
  "provider_payment_id" varchar(128) NOT NULL,
  "event" varchar(80) NOT NULL,
  "payload" jsonb NOT NULL,
  "processed_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "ai"."usage_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "request_id" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  "feature" varchar(64) NOT NULL,
  "units" integer DEFAULT 1 NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX "usage_events_request_id_unique" ON "ai"."usage_events" ("request_id");
CREATE INDEX "usage_events_user_created_at_idx" ON "ai"."usage_events" ("user_id", "created_at");
