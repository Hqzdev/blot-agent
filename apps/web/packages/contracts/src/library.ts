import { z } from 'zod';

export const libraryItemTypeSchema = z.enum(['file', 'folder', 'artifact']);
export const librarySourceSchema = z.enum(['uploaded', 'generated', 'created']);
export const libraryFileCategorySchema = z.enum([
  'image',
  'document',
  'spreadsheet',
  'presentation',
  'pdf',
  'other',
]);
export const libraryTabSchema = z.enum(['all', 'images', 'documents']);
export const librarySortSchema = z.enum(['name', 'modified', 'size']);
export const librarySortDirectionSchema = z.enum(['asc', 'desc']);

export const libraryItemSchema = z.object({
  contentType: z.string().nullable(),
  createdAt: z.coerce.date(),
  deletedAt: z.coerce.date().nullable(),
  deletionRootId: z.string().uuid().nullable(),
  documentId: z.string().uuid().nullable(),
  id: z.string().uuid(),
  itemType: libraryItemTypeSchema,
  name: z.string(),
  objectFileId: z.string().uuid().nullable(),
  ownerId: z.string().uuid(),
  parentId: z.string().uuid().nullable(),
  path: z.array(z.object({ id: z.string().uuid(), name: z.string() })),
  purgeAfter: z.coerce.date().nullable(),
  size: z.number().int().nonnegative(),
  source: librarySourceSchema,
  updatedAt: z.coerce.date(),
  url: z.string().url().nullable(),
});

export const libraryListInputSchema = z.object({
  category: libraryFileCategorySchema.optional(),
  cursor: z.string().max(128).optional(),
  deleted: z.boolean().default(false),
  direction: librarySortDirectionSchema.default('desc'),
  limit: z.number().int().min(1).max(100).default(50),
  parentId: z.string().uuid().nullable().optional(),
  query: z.string().trim().max(120).optional(),
  sort: librarySortSchema.default('modified'),
  source: z.enum(['uploaded', 'generated']).optional(),
  tab: libraryTabSchema.default('all'),
});

export const libraryListResultSchema = z.object({
  breadcrumbs: z.array(z.object({ id: z.string().uuid(), name: z.string() })),
  items: z.array(libraryItemSchema),
  nextCursor: z.string().nullable(),
});

export const libraryCreateFolderSchema = z.object({
  name: z.string().trim().min(1).max(255),
  parentId: z.string().uuid().nullable().optional(),
});

export const libraryCreateUploadSchema = z.object({
  contentType: z.string().min(1).max(255),
  name: z.string().trim().min(1).max(255),
  parentId: z.string().uuid().nullable().optional(),
  pathname: z.string().min(1).max(1024),
  size: z
    .number()
    .int()
    .positive()
    .max(25 * 1024 * 1024),
  url: z.string().url(),
});

export const libraryUpdateItemSchema = z
  .object({
    name: z.string().trim().min(1).max(255).optional(),
    parentId: z.string().uuid().nullable().optional(),
  })
  .refine((input) => input.name !== undefined || input.parentId !== undefined);

export const libraryBulkInputSchema = z
  .object({
    action: z.enum(['move', 'trash', 'restore', 'permanent']),
    ids: z.array(z.string().uuid()).min(1).max(20),
    parentId: z.string().uuid().nullable().optional(),
  })
  .refine((input) => input.action !== 'move' || input.parentId !== undefined);

export const libraryDownloadEntrySchema = z.object({
  content: z.string().nullable(),
  contentType: z.string(),
  id: z.string().uuid(),
  name: z.string(),
  path: z.string(),
  pathname: z.string().nullable(),
  size: z.number().int().nonnegative(),
  url: z.string().url().nullable(),
});

export type LibraryItemType = z.infer<typeof libraryItemTypeSchema>;
export type LibrarySource = z.infer<typeof librarySourceSchema>;
export type LibraryFileCategory = z.infer<typeof libraryFileCategorySchema>;
export type LibraryTab = z.infer<typeof libraryTabSchema>;
export type LibrarySort = z.infer<typeof librarySortSchema>;
export type LibrarySortDirection = z.infer<typeof librarySortDirectionSchema>;
export type LibraryItem = z.infer<typeof libraryItemSchema>;
export type LibraryListInput = z.infer<typeof libraryListInputSchema>;
export type LibraryListResult = z.infer<typeof libraryListResultSchema>;
export type LibraryCreateFolderInput = z.infer<
  typeof libraryCreateFolderSchema
>;
export type LibraryCreateUploadInput = z.infer<
  typeof libraryCreateUploadSchema
>;
export type LibraryUpdateItemInput = z.infer<typeof libraryUpdateItemSchema>;
export type LibraryBulkInput = z.infer<typeof libraryBulkInputSchema>;
export type LibraryDownloadEntry = z.infer<typeof libraryDownloadEntrySchema>;
