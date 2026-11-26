CREATE TABLE "conversation"."projects" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "owner_id" uuid NOT NULL,
  "name" varchar(80) NOT NULL,
  "memory_mode" varchar(24) DEFAULT 'project_only' NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "projects_memory_mode_check" CHECK ("memory_mode" = 'project_only')
);

CREATE INDEX "projects_owner_updated_at_idx" ON "conversation"."projects" ("owner_id", "updated_at");

ALTER TABLE "conversation"."chats"
ADD COLUMN "project_id" uuid;

ALTER TABLE "conversation"."chats"
ADD CONSTRAINT "chats_project_id_projects_id_fk"
FOREIGN KEY ("project_id") REFERENCES "conversation"."projects"("id")
ON DELETE CASCADE;

CREATE INDEX "chats_project_updated_at_idx" ON "conversation"."chats" ("project_id", "updated_at");

CREATE TABLE "conversation"."project_sources" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "project_id" uuid NOT NULL,
  "object_file_id" uuid NOT NULL,
  "name" varchar(255) NOT NULL,
  "extracted_text" text NOT NULL,
  "content_type" varchar(255) NOT NULL,
  "size" bigint NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "project_sources_project_id_projects_id_fk"
    FOREIGN KEY ("project_id") REFERENCES "conversation"."projects"("id")
    ON DELETE CASCADE,
  CONSTRAINT "project_sources_object_file_id_object_files_id_fk"
    FOREIGN KEY ("object_file_id") REFERENCES "conversation"."object_files"("id")
    ON DELETE CASCADE
);

CREATE INDEX "project_sources_project_created_at_idx" ON "conversation"."project_sources" ("project_id", "created_at");
CREATE UNIQUE INDEX "project_sources_object_file_unique" ON "conversation"."project_sources" ("object_file_id");
