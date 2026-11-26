import type {
  ArtifactKind,
  ChatVisibility,
  LibraryItemType,
  LibrarySource,
  ProjectMemoryMode,
  SkillCategory,
  SkillSource,
  StoredMessage,
} from '@teya/contracts';
import {
  bigint,
  boolean,
  foreignKey,
  index,
  integer,
  jsonb,
  pgSchema,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
} from 'drizzle-orm/pg-core';

export const identitySchema = pgSchema('identity');
export const conversationSchema = pgSchema('conversation');
export const billingSchema = pgSchema('billing');
export const aiSchema = pgSchema('ai');

export const blotProfiles = identitySchema.table('blot_profiles', {
  ownerId: uuid('owner_id').primaryKey(),
  nickname: varchar('nickname', { length: 80 }),
  customization: jsonb('customization'),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const users = identitySchema.table(
  'users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    email: varchar('email', { length: 320 }).notNull(),
    password: varchar('password_hash', { length: 255 }),
    nickname: varchar('nickname', { length: 32 }).notNull(),
    customization: jsonb('customization'),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    emailUnique: uniqueIndex('users_email_unique').on(table.email),
    nicknameUnique: uniqueIndex('users_nickname_unique').on(table.nickname),
  }),
);

export const projects = conversationSchema.table(
  'projects',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id').notNull(),
    name: varchar('name', { length: 80 }).notNull(),
    memoryMode: varchar('memory_mode', { length: 24 })
      .$type<ProjectMemoryMode>()
      .default('project_only')
      .notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    ownerUpdatedAt: index('projects_owner_updated_at_idx').on(
      table.ownerId,
      table.updatedAt,
    ),
  }),
);

export const chats = conversationSchema.table(
  'chats',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull(),
    title: text('title').notNull(),
    visibility: varchar('visibility', { length: 16 })
      .$type<ChatVisibility>()
      .default('private')
      .notNull(),
    projectId: uuid('project_id').references(() => projects.id, {
      onDelete: 'cascade',
    }),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    userCreatedAt: index('chats_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
    projectUpdatedAt: index('chats_project_updated_at_idx').on(
      table.projectId,
      table.updatedAt,
    ),
  }),
);

export const messages = conversationSchema.table(
  'messages',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    chatId: uuid('chat_id')
      .notNull()
      .references(() => chats.id, { onDelete: 'cascade' }),
    role: varchar('role', { length: 32 })
      .$type<StoredMessage['role']>()
      .notNull(),
    parts: jsonb('parts').$type<unknown[]>().notNull(),
    attachments: jsonb('attachments').$type<unknown[]>().default([]).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    chatCreatedAt: index('messages_chat_created_at_idx').on(
      table.chatId,
      table.createdAt,
    ),
  }),
);

export const votes = conversationSchema.table(
  'votes',
  {
    chatId: uuid('chat_id')
      .notNull()
      .references(() => chats.id, { onDelete: 'cascade' }),
    messageId: uuid('message_id')
      .notNull()
      .references(() => messages.id, { onDelete: 'cascade' }),
    isUpvoted: boolean('is_upvoted').notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    primaryKey: primaryKey({
      columns: [table.chatId, table.messageId],
    }),
  }),
);

export const documents = conversationSchema.table(
  'documents',
  {
    id: uuid('id').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    userId: uuid('user_id').notNull(),
    title: text('title').notNull(),
    content: text('content'),
    text: varchar('kind', { length: 16 })
      .$type<ArtifactKind>()
      .default('text')
      .notNull(),
  },
  (table) => ({
    primaryKey: primaryKey({
      columns: [table.id, table.createdAt],
    }),
    userCreatedAt: index('documents_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
  }),
);

export const suggestions = conversationSchema.table(
  'suggestions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    documentId: uuid('document_id').notNull(),
    documentCreatedAt: timestamp('document_created_at', {
      withTimezone: true,
    }).notNull(),
    originalText: text('original_text').notNull(),
    suggestedText: text('suggested_text').notNull(),
    description: text('description'),
    isResolved: boolean('is_resolved').default(false).notNull(),
    userId: uuid('user_id').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    documentForeignKey: foreignKey({
      columns: [table.documentId, table.documentCreatedAt],
      foreignColumns: [documents.id, documents.createdAt],
      name: 'suggestions_document_fk',
    }).onDelete('cascade'),
    documentReference: index('suggestions_document_idx').on(
      table.documentId,
      table.documentCreatedAt,
    ),
  }),
);

export const objectFiles = conversationSchema.table(
  'object_files',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull(),
    pathname: text('pathname').notNull(),
    url: text('url').notNull(),
    contentType: varchar('content_type', { length: 255 }).notNull(),
    size: bigint('size', { mode: 'number' }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    userCreatedAt: index('object_files_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
  }),
);

export const projectSources = conversationSchema.table(
  'project_sources',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    projectId: uuid('project_id')
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    objectFileId: uuid('object_file_id')
      .notNull()
      .references(() => objectFiles.id, { onDelete: 'cascade' }),
    name: varchar('name', { length: 255 }).notNull(),
    extractedText: text('extracted_text').notNull(),
    contentType: varchar('content_type', { length: 255 }).notNull(),
    size: bigint('size', { mode: 'number' }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    projectCreatedAt: index('project_sources_project_created_at_idx').on(
      table.projectId,
      table.createdAt,
    ),
    objectFileUnique: uniqueIndex('project_sources_object_file_unique').on(
      table.objectFileId,
    ),
  }),
);

export const libraryItems = conversationSchema.table(
  'library_items',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id').notNull(),
    parentId: uuid('parent_id'),
    itemType: varchar('item_type', { length: 24 })
      .$type<LibraryItemType>()
      .notNull(),
    source: varchar('source', { length: 24 }).$type<LibrarySource>().notNull(),
    objectFileId: uuid('object_file_id').references(() => objectFiles.id, {
      onDelete: 'cascade',
    }),
    documentId: uuid('document_id'),
    name: varchar('name', { length: 255 }).notNull(),
    contentType: varchar('content_type', { length: 255 }),
    size: bigint('size', { mode: 'number' }).default(0).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
    purgeAfter: timestamp('purge_after', { withTimezone: true }),
    deletionRootId: uuid('deletion_root_id'),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    ownerParentUpdatedAt: index('library_items_owner_parent_updated_idx').on(
      table.ownerId,
      table.parentId,
      table.updatedAt,
    ),
    ownerDeletedAt: index('library_items_owner_deleted_at_idx').on(
      table.ownerId,
      table.deletedAt,
    ),
    objectFileUnique: uniqueIndex('library_items_object_file_unique').on(
      table.objectFileId,
    ),
    documentUnique: uniqueIndex('library_items_document_unique').on(
      table.documentId,
    ),
    parentForeignKey: foreignKey({
      columns: [table.parentId],
      foreignColumns: [table.id],
      name: 'library_items_parent_id_library_items_id_fk',
    }).onDelete('cascade'),
  }),
);

export const plans = billingSchema.table('plans', {
  id: varchar('id', { length: 24 }).primaryKey(),
  name: varchar('name', { length: 80 }).notNull(),
  amountMinor: integer('amount_minor').notNull(),
  currency: varchar('currency', { length: 3 }).default('RUB').notNull(),
  active: boolean('active').default(true).notNull(),
});

export const subscriptions = billingSchema.table('subscriptions', {
  userId: uuid('user_id').primaryKey(),
  plan: varchar('plan', { length: 24 }).default('free').notNull(),
  status: varchar('status', { length: 24 }).default('active').notNull(),
  sourcePaymentId: uuid('source_payment_id'),
  validUntil: timestamp('valid_until', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const testSubscriptions = billingSchema.table('test_subscriptions', {
  userId: uuid('user_id').primaryKey(),
  plan: varchar('plan', { length: 24 }).notNull(),
  sourcePaymentId: uuid('source_payment_id').notNull(),
  validUntil: timestamp('valid_until', { withTimezone: true }).notNull(),
});

export const payments = billingSchema.table(
  'payments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    cardId: uuid('card_id'),
    providerPaymentId: varchar('provider_payment_id', { length: 128 }),
    idempotencyKey: uuid('idempotency_key').notNull(),
    userId: uuid('user_id').notNull(),
    plan: varchar('plan', { length: 24 }).notNull(),
    amountMinor: integer('amount_minor').notNull(),
    currency: varchar('currency', { length: 3 }).default('RUB').notNull(),
    status: varchar('status', { length: 32 }).default('pending').notNull(),
    confirmationUrl: text('confirmation_url'),
    providerPayload: jsonb('provider_payload'),
    test: boolean('test').default(true).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    idempotencyUnique: uniqueIndex('payments_idempotency_key_unique').on(
      table.idempotencyKey,
    ),
    providerPaymentUnique: uniqueIndex(
      'payments_provider_payment_id_unique',
    ).on(table.providerPaymentId),
    userCreatedAt: index('payments_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
  }),
);

export const webhookEvents = billingSchema.table('webhook_events', {
  id: uuid('id').primaryKey().defaultRandom(),
  eventKey: varchar('event_key', { length: 180 }).notNull().unique(),
  providerPaymentId: varchar('provider_payment_id', { length: 128 }).notNull(),
  event: varchar('event', { length: 80 }).notNull(),
  payload: jsonb('payload').notNull(),
  processedAt: timestamp('processed_at', { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const usageEvents = aiSchema.table(
  'usage_events',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    requestId: uuid('request_id').notNull(),
    userId: uuid('user_id').notNull(),
    feature: varchar('feature', { length: 64 }).notNull(),
    units: integer('units').default(1).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    requestUnique: uniqueIndex('usage_events_request_id_unique').on(
      table.requestId,
    ),
    userCreatedAt: index('usage_events_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
  }),
);

export const skills = aiSchema.table(
  'skills',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ownerId: uuid('owner_id'),
    source: varchar('source', { length: 24 }).$type<SkillSource>().notNull(),
    category: varchar('category', { length: 32 })
      .$type<SkillCategory>()
      .notNull(),
    name: varchar('name', { length: 80 }).notNull(),
    description: varchar('description', { length: 240 }).notNull(),
    whenToUse: varchar('when_to_use', { length: 500 }).notNull(),
    instructions: text('instructions').notNull(),
    icon: varchar('icon', { length: 48 }).notNull(),
    sortOrder: integer('sort_order').default(0).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    ownerUpdatedAt: index('skills_owner_updated_at_idx').on(
      table.ownerId,
      table.updatedAt,
    ),
    sourceCategoryOrder: index('skills_source_category_order_idx').on(
      table.source,
      table.category,
      table.sortOrder,
    ),
  }),
);

export const userSkillInstallations = aiSchema.table(
  'user_skill_installations',
  {
    userId: uuid('user_id').notNull(),
    skillId: uuid('skill_id')
      .notNull()
      .references(() => skills.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => ({
    primaryKey: primaryKey({
      columns: [table.userId, table.skillId],
    }),
    userCreatedAt: index('user_skill_installations_user_created_at_idx').on(
      table.userId,
      table.createdAt,
    ),
  }),
);

export type UserRow = typeof users.$inferSelect;
export type NewUserRow = typeof users.$inferInsert;
export type ChatRow = typeof chats.$inferSelect;
export type ProjectRow = typeof projects.$inferSelect;
export type ProjectSourceRow = typeof projectSources.$inferSelect;
export type ChatSummaryRow = ChatRow & { projectName: string | null };
export type MessageRow = typeof messages.$inferSelect;
export type VoteRow = typeof votes.$inferSelect;
export type DocumentRow = typeof documents.$inferSelect;
export type SuggestionRow = typeof suggestions.$inferSelect;
export type ObjectFileRow = typeof objectFiles.$inferSelect;
export type LibraryItemRow = typeof libraryItems.$inferSelect;
export type PlanRow = typeof plans.$inferSelect;
export type SubscriptionRow = typeof subscriptions.$inferSelect;
export type PaymentRow = typeof payments.$inferSelect;
export type SkillRow = typeof skills.$inferSelect;
export type NewSkillRow = typeof skills.$inferInsert;
export type SkillInstallationRow = typeof userSkillInstallations.$inferSelect;
