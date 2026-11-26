import { z } from 'zod';
import {
  libraryBulkInputSchema,
  libraryCreateFolderSchema,
  libraryCreateUploadSchema,
  libraryListInputSchema,
  libraryUpdateItemSchema,
} from './library';

export const artifactKindSchema = z.enum(['text', 'code', 'image', 'sheet']);
export const chatVisibilitySchema = z.enum(['public', 'private']);
export const projectMemoryModeSchema = z.literal('project_only');
export const messageRoleSchema = z.enum([
  'assistant',
  'data',
  'system',
  'tool',
  'user',
]);

export const storedMessageSchema = z.object({
  attachments: z.array(z.unknown()),
  chatId: z.string().uuid(),
  createdAt: z.coerce.date(),
  id: z.string().uuid(),
  parts: z.array(z.unknown()).min(1),
  role: messageRoleSchema,
});

export const conversationOperationSchema = z.discriminatedUnion('operation', [
  z.object({
    operation: z.literal('getChats'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('getChat'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('saveChat'),
    payload: z.object({
      id: z.string().uuid(),
      projectId: z.string().uuid().optional(),
      title: z.string().min(1).max(200),
    }),
  }),
  z.object({
    operation: z.literal('getProjects'),
    payload: z.object({
      query: z.string().trim().max(80).optional(),
    }),
  }),
  z.object({
    operation: z.literal('getProject'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('createProject'),
    payload: z.object({
      name: z.string().trim().min(1).max(80),
    }),
  }),
  z.object({
    operation: z.literal('updateProject'),
    payload: z.object({
      id: z.string().uuid(),
      name: z.string().trim().min(1).max(80),
    }),
  }),
  z.object({
    operation: z.literal('deleteProject'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getProjectChats'),
    payload: z.object({ projectId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getProjectSources'),
    payload: z.object({ projectId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('saveProjectSource'),
    payload: z.object({
      contentType: z.string().min(1).max(255),
      extractedText: z.string().min(1).max(200_000),
      name: z.string().trim().min(1).max(255),
      pathname: z.string().min(1).max(1024),
      projectId: z.string().uuid(),
      size: z
        .number()
        .int()
        .positive()
        .max(5 * 1024 * 1024),
      url: z.string().url(),
    }),
  }),
  z.object({
    operation: z.literal('deleteProjectSource'),
    payload: z.object({
      projectId: z.string().uuid(),
      sourceId: z.string().uuid(),
    }),
  }),
  z.object({
    operation: z.literal('getProjectContext'),
    payload: z.object({
      currentChatId: z.string().uuid(),
      projectId: z.string().uuid(),
    }),
  }),
  z.object({
    operation: z.literal('deleteChat'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getMessages'),
    payload: z.object({ chatId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('saveMessages'),
    payload: z.object({ messages: z.array(storedMessageSchema).min(1) }),
  }),
  z.object({
    operation: z.literal('getVotes'),
    payload: z.object({ chatId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('vote'),
    payload: z.object({
      chatId: z.string().uuid(),
      messageId: z.string().uuid(),
      type: z.enum(['up', 'down']),
    }),
  }),
  z.object({
    operation: z.literal('getDocument'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getDocuments'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('saveDocument'),
    payload: z.object({
      content: z.string(),
      id: z.string().uuid(),
      kind: artifactKindSchema,
      title: z.string().min(1).max(300),
    }),
  }),
  z.object({
    operation: z.literal('deleteDocumentsAfter'),
    payload: z.object({
      id: z.string().uuid(),
      timestamp: z.coerce.date(),
    }),
  }),
  z.object({
    operation: z.literal('getSuggestions'),
    payload: z.object({ documentId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('saveSuggestions'),
    payload: z.object({
      suggestions: z
        .array(
          z.object({
            createdAt: z.coerce.date(),
            description: z.string().nullable(),
            documentCreatedAt: z.coerce.date(),
            documentId: z.string().uuid(),
            id: z.string().uuid(),
            isResolved: z.boolean(),
            originalText: z.string(),
            suggestedText: z.string(),
          }),
        )
        .min(1),
    }),
  }),
  z.object({
    operation: z.literal('getMessage'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('deleteMessagesAfter'),
    payload: z.object({
      chatId: z.string().uuid(),
      timestamp: z.coerce.date(),
    }),
  }),
  z.object({
    operation: z.literal('updateVisibility'),
    payload: z.object({
      chatId: z.string().uuid(),
      visibility: chatVisibilitySchema,
    }),
  }),
  z.object({
    operation: z.literal('deleteUserData'),
    payload: z.object({ userId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getObjectFiles'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('saveObjectFile'),
    payload: z.object({
      contentType: z.string().min(1).max(255),
      pathname: z.string().min(1).max(1024),
      size: z
        .number()
        .int()
        .positive()
        .max(5 * 1024 * 1024),
      url: z.string().url(),
    }),
  }),
  z.object({
    operation: z.literal('listLibraryItems'),
    payload: libraryListInputSchema,
  }),
  z.object({
    operation: z.literal('getLibraryItem'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('createLibraryFolder'),
    payload: libraryCreateFolderSchema,
  }),
  z.object({
    operation: z.literal('createLibraryUpload'),
    payload: libraryCreateUploadSchema,
  }),
  z.object({
    operation: z.literal('updateLibraryItem'),
    payload: z.object({ id: z.string().uuid() }).and(libraryUpdateItemSchema),
  }),
  z.object({
    operation: z.literal('trashLibraryItems'),
    payload: z.object({ ids: z.array(z.string().uuid()).min(1).max(20) }),
  }),
  z.object({
    operation: z.literal('restoreLibraryItems'),
    payload: z.object({ ids: z.array(z.string().uuid()).min(1).max(20) }),
  }),
  z.object({
    operation: z.literal('permanentlyDeleteLibraryItems'),
    payload: z.object({ ids: z.array(z.string().uuid()).min(1).max(20) }),
  }),
  z.object({
    operation: z.literal('bulkLibraryItems'),
    payload: libraryBulkInputSchema,
  }),
  z.object({
    operation: z.literal('getLibraryDownloadManifest'),
    payload: z.object({ ids: z.array(z.string().uuid()).min(1).max(20) }),
  }),
  z.object({
    operation: z.literal('getExpiredLibraryItems'),
    payload: z.object({ now: z.coerce.date() }),
  }),
  z.object({
    operation: z.literal('purgeExpiredLibraryItems'),
    payload: z.object({ ids: z.array(z.string().uuid()).min(1).max(100) }),
  }),
]);

export type ArtifactKind = z.infer<typeof artifactKindSchema>;
export type ChatVisibility = z.infer<typeof chatVisibilitySchema>;
export type ProjectMemoryMode = z.infer<typeof projectMemoryModeSchema>;
export type StoredMessage = z.infer<typeof storedMessageSchema>;
export type ConversationOperation = z.infer<typeof conversationOperationSchema>;
