CREATE TABLE "conversation"."library_items" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "owner_id" uuid NOT NULL,
  "parent_id" uuid,
  "item_type" varchar(24) NOT NULL,
  "source" varchar(24) NOT NULL,
  "object_file_id" uuid,
  "document_id" uuid,
  "name" varchar(255) NOT NULL,
  "content_type" varchar(255),
  "size" bigint DEFAULT 0 NOT NULL,
  "deleted_at" timestamp with time zone,
  "purge_after" timestamp with time zone,
  "deletion_root_id" uuid,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "library_items_item_type_check"
    CHECK ("item_type" IN ('file', 'folder', 'artifact')),
  CONSTRAINT "library_items_source_check"
    CHECK ("source" IN ('uploaded', 'generated', 'created')),
  CONSTRAINT "library_items_name_length_check"
    CHECK (char_length(btrim("name")) BETWEEN 1 AND 255),
  CONSTRAINT "library_items_backing_check" CHECK (
    ("item_type" = 'folder' AND "object_file_id" IS NULL AND "document_id" IS NULL) OR
    ("item_type" = 'file' AND "object_file_id" IS NOT NULL AND "document_id" IS NULL) OR
    ("item_type" = 'artifact' AND "object_file_id" IS NULL AND "document_id" IS NOT NULL)
  ),
  CONSTRAINT "library_items_parent_id_library_items_id_fk"
    FOREIGN KEY ("parent_id") REFERENCES "conversation"."library_items"("id")
    ON DELETE CASCADE,
  CONSTRAINT "library_items_object_file_id_object_files_id_fk"
    FOREIGN KEY ("object_file_id") REFERENCES "conversation"."object_files"("id")
    ON DELETE CASCADE
);

CREATE INDEX "library_items_owner_parent_updated_idx"
  ON "conversation"."library_items" ("owner_id", "parent_id", "updated_at");
CREATE INDEX "library_items_owner_deleted_at_idx"
  ON "conversation"."library_items" ("owner_id", "deleted_at");
CREATE UNIQUE INDEX "library_items_object_file_unique"
  ON "conversation"."library_items" ("object_file_id");
CREATE UNIQUE INDEX "library_items_document_unique"
  ON "conversation"."library_items" ("document_id");

INSERT INTO "conversation"."library_items" (
  "owner_id",
  "item_type",
  "source",
  "object_file_id",
  "name",
  "content_type",
  "size",
  "created_at",
  "updated_at"
)
SELECT
  stored."user_id",
  'file',
  'uploaded',
  stored."id",
  LEFT(
    COALESCE(
      source_file."name",
      attachment_file."name",
      NULLIF(regexp_replace(stored."pathname", '^.*/', ''), ''),
      'File'
    ),
    255
  ),
  stored."content_type",
  stored."size",
  stored."created_at",
  stored."created_at"
FROM "conversation"."object_files" stored
LEFT JOIN LATERAL (
  SELECT source."name"
  FROM "conversation"."project_sources" source
  WHERE source."object_file_id" = stored."id"
  LIMIT 1
) source_file ON TRUE
LEFT JOIN LATERAL (
  SELECT attachment->>'name' AS "name"
  FROM "conversation"."messages" message,
    LATERAL jsonb_array_elements(message."attachments") attachment
  WHERE attachment->>'url' = stored."url"
    AND NULLIF(attachment->>'name', '') IS NOT NULL
  ORDER BY message."created_at" DESC
  LIMIT 1
) attachment_file ON TRUE
ON CONFLICT ("object_file_id") DO NOTHING;

INSERT INTO "conversation"."library_items" (
  "owner_id",
  "item_type",
  "source",
  "document_id",
  "name",
  "content_type",
  "size",
  "created_at",
  "updated_at"
)
SELECT
  latest."user_id",
  'artifact',
  'generated',
  latest."id",
  LEFT(
    CASE latest."kind"
      WHEN 'text' THEN
        CASE WHEN latest."title" ~* '\.md$' THEN latest."title" ELSE latest."title" || '.md' END
      WHEN 'code' THEN
        CASE WHEN latest."title" ~* '\.txt$' THEN latest."title" ELSE latest."title" || '.txt' END
      WHEN 'sheet' THEN
        CASE WHEN latest."title" ~* '\.csv$' THEN latest."title" ELSE latest."title" || '.csv' END
      WHEN 'image' THEN
        CASE WHEN latest."title" ~* '\.png$' THEN latest."title" ELSE latest."title" || '.png' END
      ELSE latest."title"
    END,
    255
  ),
  CASE latest."kind"
    WHEN 'text' THEN 'text/markdown'
    WHEN 'code' THEN 'text/plain'
    WHEN 'sheet' THEN 'text/csv'
    WHEN 'image' THEN 'image/png'
    ELSE 'application/octet-stream'
  END,
  CASE
    WHEN latest."kind" = 'image'
      THEN floor(length(COALESCE(latest."content", '')) * 0.75)::bigint
    ELSE octet_length(COALESCE(latest."content", ''))::bigint
  END,
  earliest."created_at",
  latest."created_at"
FROM (
  SELECT DISTINCT ON ("id")
    "id", "user_id", "title", "content", "kind", "created_at"
  FROM "conversation"."documents"
  ORDER BY "id", "created_at" DESC
) latest
JOIN (
  SELECT "id", min("created_at") AS "created_at"
  FROM "conversation"."documents"
  GROUP BY "id"
) earliest ON earliest."id" = latest."id"
ON CONFLICT ("document_id") DO NOTHING;
