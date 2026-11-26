import type {
  ArtifactKind,
  ChatVisibility,
  LibraryCreateUploadInput,
  StoredMessage,
} from '@teya/contracts';
import {
  type ChatRow,
  type ChatSummaryRow,
  DatabaseConnectionProvider,
  type DocumentRow,
  type LibraryItemRow,
  type MessageRow,
  type ObjectFileRow,
  type ProjectRow,
  type ProjectSourceRow,
  type SuggestionRow,
  type VoteRow,
  chats,
  documents,
  libraryItems,
  messages,
  objectFiles,
  projectSources,
  projects,
  suggestions,
  votes,
} from '@teya/database';
import {
  and,
  asc,
  desc,
  eq,
  gt,
  gte,
  ilike,
  inArray,
  isNotNull,
  isNull,
  lte,
  ne,
  sql,
} from 'drizzle-orm';

export type LibraryItemRecord = LibraryItemRow & { url: string | null };

export type LibraryDownloadRecord = LibraryItemRecord & {
  content: string | null;
  pathname: string | null;
};

export interface LibraryRepository {
  createLibraryFolder(input: {
    name: string;
    ownerId: string;
    parentId: string | null;
  }): Promise<LibraryItemRecord>;
  createLibraryUpload(
    input: LibraryCreateUploadInput & {
      ownerId: string;
      parentId: string | null;
    },
  ): Promise<LibraryItemRecord>;
  deleteLibraryItems(ids: string[]): Promise<string[]>;
  findExpiredLibraryRootIds(now: Date): Promise<string[]>;
  findLibraryDownloadRecords(ids: string[]): Promise<LibraryDownloadRecord[]>;
  findLibraryItem(id: string): Promise<LibraryItemRecord | undefined>;
  findLibraryItems(ownerId: string): Promise<LibraryItemRecord[]>;
  isLibraryDocumentAvailable(
    ownerId: string,
    documentId: string,
  ): Promise<boolean>;
  restoreLibraryItems(rootIds: string[]): Promise<void>;
  trashLibraryItems(
    groups: Array<{ ids: string[]; rootId: string }>,
    deletedAt: Date,
    purgeAfter: Date,
  ): Promise<void>;
  updateLibraryItem(
    id: string,
    input: { name?: string; parentId?: string | null },
  ): Promise<LibraryItemRecord>;
}

export interface SaveMessageInput {
  attachments: unknown[];
  chatId: string;
  createdAt: Date;
  id: string;
  parts: unknown[];
  role: StoredMessage['role'];
}

export interface SaveSuggestionInput {
  createdAt: Date;
  description: string | null;
  documentCreatedAt: Date;
  documentId: string;
  id: string;
  isResolved: boolean;
  originalText: string;
  suggestedText: string;
  userId: string;
}

function getArtifactFileMetadata(
  kind: ArtifactKind,
  title: string,
  content: string,
) {
  const definition = {
    code: { contentType: 'text/plain', extension: '.txt' },
    image: { contentType: 'image/png', extension: '.png' },
    sheet: { contentType: 'text/csv', extension: '.csv' },
    text: { contentType: 'text/markdown', extension: '.md' },
  }[kind];
  const name = title.toLocaleLowerCase().endsWith(definition.extension)
    ? title
    : `${title}${definition.extension}`;
  return {
    contentType: definition.contentType,
    name: name.slice(0, 255),
    size:
      kind === 'image'
        ? Math.floor(content.length * 0.75)
        : Buffer.byteLength(content),
  };
}

export type ProjectSummary = ProjectRow & {
  chatCount: number;
  sourceCount: number;
};

export type ProjectSourceSummary = Omit<ProjectSourceRow, 'extractedText'>;

export interface ProjectContextMessage {
  chatTitle: string;
  createdAt: Date;
  parts: unknown[];
  role: StoredMessage['role'];
}

export interface ProjectContextSource {
  extractedText: string;
  name: string;
}

export interface ConversationRepository extends LibraryRepository {
  deleteChat(id: string): Promise<void>;
  deleteDocumentsAfter(id: string, timestamp: Date): Promise<void>;
  deleteMessagesAfter(chatId: string, timestamp: Date): Promise<void>;
  deleteUserData(userId: string): Promise<void>;
  findChat(id: string): Promise<ChatRow | undefined>;
  deleteProject(id: string): Promise<string[]>;
  deleteProjectSource(sourceId: string): Promise<string>;
  findChats(userId: string): Promise<ChatSummaryRow[]>;
  findDocument(id: string): Promise<DocumentRow | undefined>;
  findDocuments(id: string): Promise<DocumentRow[]>;
  findMessage(id: string): Promise<MessageRow | undefined>;
  findMessages(chatId: string): Promise<MessageRow[]>;
  findObjectFiles(userId: string): Promise<ObjectFileRow[]>;
  findProject(id: string): Promise<ProjectRow | undefined>;
  findProjectChats(projectId: string): Promise<ChatSummaryRow[]>;
  findProjectContextMessages(
    projectId: string,
    currentChatId: string,
  ): Promise<ProjectContextMessage[]>;
  findProjectContextSources(projectId: string): Promise<ProjectContextSource[]>;
  findProjects(userId: string, query?: string): Promise<ProjectSummary[]>;
  findProjectSource(sourceId: string): Promise<ProjectSourceRow | undefined>;
  findProjectSources(projectId: string): Promise<ProjectSourceSummary[]>;
  findSuggestions(documentId: string): Promise<SuggestionRow[]>;
  findVotes(chatId: string): Promise<VoteRow[]>;
  saveChat(
    id: string,
    userId: string,
    title: string,
    projectId?: string,
  ): Promise<ChatRow>;
  saveDocument(input: {
    content: string;
    id: string;
    kind: ArtifactKind;
    title: string;
    userId: string;
  }): Promise<DocumentRow>;
  saveMessages(input: SaveMessageInput[]): Promise<void>;
  saveObjectFile(input: {
    contentType: string;
    pathname: string;
    size: number;
    url: string;
    userId: string;
  }): Promise<ObjectFileRow>;
  saveProject(ownerId: string, name: string): Promise<ProjectRow>;
  saveProjectSource(input: {
    contentType: string;
    extractedText: string;
    name: string;
    pathname: string;
    projectId: string;
    size: number;
    url: string;
    userId: string;
  }): Promise<ProjectSourceSummary>;
  saveSuggestions(input: SaveSuggestionInput[]): Promise<void>;
  updateVisibility(chatId: string, visibility: ChatVisibility): Promise<void>;
  updateProject(id: string, name: string): Promise<ProjectRow>;
  vote(chatId: string, messageId: string, isUpvoted: boolean): Promise<void>;
}

export class PostgresConversationRepository implements ConversationRepository {
  private readonly db = new DatabaseConnectionProvider().get().db;

  async createLibraryFolder(input: {
    name: string;
    ownerId: string;
    parentId: string | null;
  }): Promise<LibraryItemRecord> {
    const [created] = await this.db
      .insert(libraryItems)
      .values({
        itemType: 'folder',
        name: input.name,
        ownerId: input.ownerId,
        parentId: input.parentId,
        source: 'created',
      })
      .returning();
    if (!created) {
      throw new Error('Library folder creation returned no row');
    }
    return { ...created, url: null };
  }

  async createLibraryUpload(
    input: LibraryCreateUploadInput & {
      ownerId: string;
      parentId: string | null;
    },
  ): Promise<LibraryItemRecord> {
    return this.db.transaction(async (transaction) => {
      const [storedFile] = await transaction
        .insert(objectFiles)
        .values({
          contentType: input.contentType,
          pathname: input.pathname,
          size: input.size,
          url: input.url,
          userId: input.ownerId,
        })
        .returning();
      if (!storedFile) {
        throw new Error('Object file creation returned no row');
      }
      const [created] = await transaction
        .insert(libraryItems)
        .values({
          contentType: input.contentType,
          itemType: 'file',
          name: input.name,
          objectFileId: storedFile.id,
          ownerId: input.ownerId,
          parentId: input.parentId,
          size: input.size,
          source: 'uploaded',
        })
        .returning();
      if (!created) {
        throw new Error('Library item creation returned no row');
      }
      return { ...created, url: storedFile.url };
    });
  }

  async deleteLibraryItems(ids: string[]): Promise<string[]> {
    if (ids.length === 0) {
      return [];
    }
    return this.db.transaction(async (transaction) => {
      const selected = await transaction
        .select()
        .from(libraryItems)
        .where(inArray(libraryItems.id, ids));
      const objectFileIds = selected.flatMap((item) =>
        item.objectFileId ? [item.objectFileId] : [],
      );
      const documentIds = selected.flatMap((item) =>
        item.documentId ? [item.documentId] : [],
      );
      const storedFiles =
        objectFileIds.length > 0
          ? await transaction
              .select({ pathname: objectFiles.pathname })
              .from(objectFiles)
              .where(inArray(objectFiles.id, objectFileIds))
          : [];
      await transaction
        .delete(libraryItems)
        .where(inArray(libraryItems.id, ids));
      if (documentIds.length > 0) {
        await transaction
          .delete(documents)
          .where(inArray(documents.id, documentIds));
      }
      if (objectFileIds.length > 0) {
        await transaction
          .delete(objectFiles)
          .where(inArray(objectFiles.id, objectFileIds));
      }
      return storedFiles.map((file) => file.pathname);
    });
  }

  async findExpiredLibraryRootIds(now: Date): Promise<string[]> {
    const rows = await this.db
      .select({ id: libraryItems.id })
      .from(libraryItems)
      .where(
        and(
          isNotNull(libraryItems.deletedAt),
          lte(libraryItems.purgeAfter, now),
          eq(libraryItems.deletionRootId, libraryItems.id),
        ),
      );
    return rows.map((row) => row.id);
  }

  async findLibraryDownloadRecords(
    ids: string[],
  ): Promise<LibraryDownloadRecord[]> {
    if (ids.length === 0) {
      return [];
    }
    const rows = await this.db
      .select({
        item: libraryItems,
        pathname: objectFiles.pathname,
        url: objectFiles.url,
      })
      .from(libraryItems)
      .leftJoin(objectFiles, eq(libraryItems.objectFileId, objectFiles.id))
      .where(inArray(libraryItems.id, ids));
    const documentIds = rows.flatMap((row) =>
      row.item.documentId ? [row.item.documentId] : [],
    );
    const documentRows =
      documentIds.length > 0
        ? await this.db
            .select()
            .from(documents)
            .where(inArray(documents.id, documentIds))
            .orderBy(desc(documents.createdAt))
        : [];
    const latestContent = new Map<string, string | null>();
    for (const document of documentRows) {
      if (!latestContent.has(document.id)) {
        latestContent.set(document.id, document.content);
      }
    }
    return rows.map((row) => ({
      ...row.item,
      content: row.item.documentId
        ? (latestContent.get(row.item.documentId) ?? null)
        : null,
      pathname: row.pathname,
      url: row.url,
    }));
  }

  async findLibraryItem(id: string): Promise<LibraryItemRecord | undefined> {
    const [row] = await this.db
      .select({ item: libraryItems, url: objectFiles.url })
      .from(libraryItems)
      .leftJoin(objectFiles, eq(libraryItems.objectFileId, objectFiles.id))
      .where(eq(libraryItems.id, id))
      .limit(1);
    return row ? { ...row.item, url: row.url } : undefined;
  }

  async findLibraryItems(ownerId: string): Promise<LibraryItemRecord[]> {
    const rows = await this.db
      .select({ item: libraryItems, url: objectFiles.url })
      .from(libraryItems)
      .leftJoin(objectFiles, eq(libraryItems.objectFileId, objectFiles.id))
      .where(eq(libraryItems.ownerId, ownerId));
    return rows.map((row) => ({ ...row.item, url: row.url }));
  }

  async isLibraryDocumentAvailable(
    ownerId: string,
    documentId: string,
  ): Promise<boolean> {
    const [row] = await this.db
      .select({ id: libraryItems.id })
      .from(libraryItems)
      .where(
        and(
          eq(libraryItems.ownerId, ownerId),
          eq(libraryItems.documentId, documentId),
          isNull(libraryItems.deletedAt),
        ),
      )
      .limit(1);
    return Boolean(row);
  }

  async restoreLibraryItems(rootIds: string[]): Promise<void> {
    if (rootIds.length === 0) {
      return;
    }
    await this.db
      .update(libraryItems)
      .set({
        deletedAt: null,
        deletionRootId: null,
        purgeAfter: null,
        updatedAt: new Date(),
      })
      .where(inArray(libraryItems.deletionRootId, rootIds));
  }

  async trashLibraryItems(
    groups: Array<{ ids: string[]; rootId: string }>,
    deletedAt: Date,
    purgeAfter: Date,
  ): Promise<void> {
    await this.db.transaction(async (transaction) => {
      for (const group of groups) {
        if (group.ids.length === 0) {
          continue;
        }
        await transaction
          .update(libraryItems)
          .set({
            deletedAt,
            deletionRootId: group.rootId,
            purgeAfter,
            updatedAt: deletedAt,
          })
          .where(inArray(libraryItems.id, group.ids));
      }
    });
  }

  async updateLibraryItem(
    id: string,
    input: { name?: string; parentId?: string | null },
  ): Promise<LibraryItemRecord> {
    const values: { name?: string; parentId?: string | null; updatedAt: Date } =
      {
        updatedAt: new Date(),
      };
    if (input.name !== undefined) {
      values.name = input.name;
    }
    if (input.parentId !== undefined) {
      values.parentId = input.parentId;
    }
    const [updated] = await this.db
      .update(libraryItems)
      .set(values)
      .where(eq(libraryItems.id, id))
      .returning();
    if (!updated) {
      throw new Error('Library item update returned no row');
    }
    const storedFile = updated.objectFileId
      ? await this.db
          .select({ url: objectFiles.url })
          .from(objectFiles)
          .where(eq(objectFiles.id, updated.objectFileId))
          .limit(1)
      : [];
    return { ...updated, url: storedFile[0]?.url ?? null };
  }

  async deleteChat(id: string): Promise<void> {
    await this.db.delete(chats).where(eq(chats.id, id));
  }

  async deleteProject(id: string): Promise<string[]> {
    return this.db.transaction(async (transaction) => {
      const storedFiles = await transaction
        .select({
          id: objectFiles.id,
          pathname: objectFiles.pathname,
        })
        .from(projectSources)
        .innerJoin(objectFiles, eq(projectSources.objectFileId, objectFiles.id))
        .where(eq(projectSources.projectId, id));
      await transaction.delete(projects).where(eq(projects.id, id));
      const fileIds = storedFiles.map((file) => file.id);
      if (fileIds.length > 0) {
        await transaction
          .delete(objectFiles)
          .where(inArray(objectFiles.id, fileIds));
      }
      return storedFiles.map((file) => file.pathname);
    });
  }

  async deleteProjectSource(sourceId: string): Promise<string> {
    return this.db.transaction(async (transaction) => {
      const [storedFile] = await transaction
        .select({
          id: objectFiles.id,
          pathname: objectFiles.pathname,
          projectId: projectSources.projectId,
        })
        .from(projectSources)
        .innerJoin(objectFiles, eq(projectSources.objectFileId, objectFiles.id))
        .where(eq(projectSources.id, sourceId))
        .limit(1);
      if (!storedFile) {
        throw new Error('Project source file not found');
      }
      await transaction
        .delete(projectSources)
        .where(eq(projectSources.id, sourceId));
      await transaction
        .delete(objectFiles)
        .where(eq(objectFiles.id, storedFile.id));
      await transaction
        .update(projects)
        .set({ updatedAt: new Date() })
        .where(eq(projects.id, storedFile.projectId));
      return storedFile.pathname;
    });
  }

  async deleteDocumentsAfter(id: string, timestamp: Date): Promise<void> {
    await this.db
      .delete(suggestions)
      .where(
        and(
          eq(suggestions.documentId, id),
          gt(suggestions.documentCreatedAt, timestamp),
        ),
      );
    await this.db
      .delete(documents)
      .where(and(eq(documents.id, id), gt(documents.createdAt, timestamp)));
  }

  async deleteMessagesAfter(chatId: string, timestamp: Date): Promise<void> {
    const selected = await this.db
      .select({ id: messages.id })
      .from(messages)
      .where(
        and(eq(messages.chatId, chatId), gte(messages.createdAt, timestamp)),
      );
    const ids = selected.map((message) => message.id);
    if (ids.length > 0) {
      await this.db
        .delete(messages)
        .where(and(eq(messages.chatId, chatId), inArray(messages.id, ids)));
    }
  }

  async deleteUserData(userId: string): Promise<void> {
    const userChats = await this.db
      .select({ id: chats.id })
      .from(chats)
      .where(eq(chats.userId, userId));
    const chatIds = userChats.map((chat) => chat.id);
    if (chatIds.length > 0) {
      await this.db.delete(chats).where(inArray(chats.id, chatIds));
    }
    await this.db.delete(suggestions).where(eq(suggestions.userId, userId));
    await this.db.delete(libraryItems).where(eq(libraryItems.ownerId, userId));
    await this.db.delete(documents).where(eq(documents.userId, userId));
    await this.db.delete(projects).where(eq(projects.ownerId, userId));
    await this.db.delete(objectFiles).where(eq(objectFiles.userId, userId));
  }

  async findChat(id: string): Promise<ChatRow | undefined> {
    const [chat] = await this.db
      .select()
      .from(chats)
      .where(eq(chats.id, id))
      .limit(1);
    return chat;
  }

  findChats(userId: string): Promise<ChatSummaryRow[]> {
    return this.db
      .select({
        id: chats.id,
        userId: chats.userId,
        title: chats.title,
        visibility: chats.visibility,
        projectId: chats.projectId,
        projectName: projects.name,
        createdAt: chats.createdAt,
        updatedAt: chats.updatedAt,
      })
      .from(chats)
      .leftJoin(projects, eq(chats.projectId, projects.id))
      .where(eq(chats.userId, userId))
      .orderBy(desc(chats.updatedAt));
  }

  async findDocument(id: string): Promise<DocumentRow | undefined> {
    const [document] = await this.db
      .select()
      .from(documents)
      .where(eq(documents.id, id))
      .orderBy(desc(documents.createdAt))
      .limit(1);
    return document;
  }

  findDocuments(id: string): Promise<DocumentRow[]> {
    return this.db
      .select()
      .from(documents)
      .where(eq(documents.id, id))
      .orderBy(asc(documents.createdAt));
  }

  async findMessage(id: string): Promise<MessageRow | undefined> {
    const [message] = await this.db
      .select()
      .from(messages)
      .where(eq(messages.id, id))
      .limit(1);
    return message;
  }

  findMessages(chatId: string): Promise<MessageRow[]> {
    return this.db
      .select()
      .from(messages)
      .where(eq(messages.chatId, chatId))
      .orderBy(
        asc(
          sql`(SELECT position FROM blot_web.message_order WHERE message_id=${messages.id})`,
        ),
        asc(messages.createdAt),
        asc(messages.id),
      );
  }

  findObjectFiles(userId: string): Promise<ObjectFileRow[]> {
    return this.db
      .select()
      .from(objectFiles)
      .where(eq(objectFiles.userId, userId))
      .orderBy(asc(objectFiles.createdAt));
  }

  async findProject(id: string): Promise<ProjectRow | undefined> {
    const [project] = await this.db
      .select()
      .from(projects)
      .where(eq(projects.id, id))
      .limit(1);
    return project;
  }

  findProjectChats(projectId: string): Promise<ChatSummaryRow[]> {
    return this.db
      .select({
        id: chats.id,
        userId: chats.userId,
        title: chats.title,
        visibility: chats.visibility,
        projectId: chats.projectId,
        projectName: projects.name,
        createdAt: chats.createdAt,
        updatedAt: chats.updatedAt,
      })
      .from(chats)
      .innerJoin(projects, eq(chats.projectId, projects.id))
      .where(eq(chats.projectId, projectId))
      .orderBy(desc(chats.updatedAt));
  }

  findProjectContextMessages(
    projectId: string,
    currentChatId: string,
  ): Promise<ProjectContextMessage[]> {
    return this.db
      .select({
        chatTitle: chats.title,
        createdAt: messages.createdAt,
        parts: messages.parts,
        role: messages.role,
      })
      .from(messages)
      .innerJoin(chats, eq(messages.chatId, chats.id))
      .where(and(eq(chats.projectId, projectId), ne(chats.id, currentChatId)))
      .orderBy(desc(messages.createdAt))
      .limit(20);
  }

  findProjectContextSources(
    projectId: string,
  ): Promise<ProjectContextSource[]> {
    return this.db
      .select({
        extractedText: projectSources.extractedText,
        name: projectSources.name,
      })
      .from(projectSources)
      .innerJoin(
        libraryItems,
        eq(projectSources.objectFileId, libraryItems.objectFileId),
      )
      .where(
        and(
          eq(projectSources.projectId, projectId),
          isNull(libraryItems.deletedAt),
        ),
      )
      .orderBy(desc(projectSources.updatedAt));
  }

  async findProjects(
    userId: string,
    query?: string,
  ): Promise<ProjectSummary[]> {
    const rows = await this.db
      .select()
      .from(projects)
      .where(
        query
          ? and(
              eq(projects.ownerId, userId),
              ilike(projects.name, `%${query}%`),
            )
          : eq(projects.ownerId, userId),
      )
      .orderBy(desc(projects.updatedAt));
    return Promise.all(
      rows.map(async (project) => {
        const [projectChats, sources] = await Promise.all([
          this.db
            .select({ id: chats.id })
            .from(chats)
            .where(eq(chats.projectId, project.id)),
          this.db
            .select({ id: projectSources.id })
            .from(projectSources)
            .innerJoin(
              libraryItems,
              eq(projectSources.objectFileId, libraryItems.objectFileId),
            )
            .where(
              and(
                eq(projectSources.projectId, project.id),
                isNull(libraryItems.deletedAt),
              ),
            ),
        ]);
        return {
          ...project,
          chatCount: projectChats.length,
          sourceCount: sources.length,
        };
      }),
    );
  }

  async findProjectSource(
    sourceId: string,
  ): Promise<ProjectSourceRow | undefined> {
    const [source] = await this.db
      .select()
      .from(projectSources)
      .where(eq(projectSources.id, sourceId))
      .limit(1);
    return source;
  }

  findProjectSources(projectId: string): Promise<ProjectSourceSummary[]> {
    return this.db
      .select({
        id: projectSources.id,
        projectId: projectSources.projectId,
        objectFileId: projectSources.objectFileId,
        name: projectSources.name,
        contentType: projectSources.contentType,
        size: projectSources.size,
        createdAt: projectSources.createdAt,
        updatedAt: projectSources.updatedAt,
      })
      .from(projectSources)
      .innerJoin(
        libraryItems,
        eq(projectSources.objectFileId, libraryItems.objectFileId),
      )
      .where(
        and(
          eq(projectSources.projectId, projectId),
          isNull(libraryItems.deletedAt),
        ),
      )
      .orderBy(desc(projectSources.createdAt));
  }

  findSuggestions(documentId: string): Promise<SuggestionRow[]> {
    return this.db
      .select()
      .from(suggestions)
      .where(eq(suggestions.documentId, documentId))
      .orderBy(asc(suggestions.createdAt));
  }

  findVotes(chatId: string): Promise<VoteRow[]> {
    return this.db.select().from(votes).where(eq(votes.chatId, chatId));
  }

  async saveChat(
    id: string,
    userId: string,
    title: string,
    projectId?: string,
  ): Promise<ChatRow> {
    const [created] = await this.db
      .insert(chats)
      .values({ id, projectId, title, userId, visibility: 'private' })
      .returning();
    if (!created) {
      throw new Error('Chat creation returned no row');
    }
    if (projectId) {
      await this.db
        .update(projects)
        .set({ updatedAt: new Date() })
        .where(eq(projects.id, projectId));
    }
    return created;
  }

  async saveDocument(input: {
    content: string;
    id: string;
    kind: ArtifactKind;
    title: string;
    userId: string;
  }): Promise<DocumentRow> {
    return this.db.transaction(async (transaction) => {
      const [created] = await transaction
        .insert(documents)
        .values({
          content: input.content,
          id: input.id,
          text: input.kind,
          title: input.title,
          userId: input.userId,
        })
        .returning();
      if (!created) {
        throw new Error('Document creation returned no row');
      }
      const metadata = getArtifactFileMetadata(
        input.kind,
        input.title,
        input.content,
      );
      await transaction
        .insert(libraryItems)
        .values({
          contentType: metadata.contentType,
          documentId: input.id,
          itemType: 'artifact',
          name: metadata.name,
          ownerId: input.userId,
          size: metadata.size,
          source: 'generated',
          updatedAt: created.createdAt,
        })
        .onConflictDoUpdate({
          set: {
            contentType: metadata.contentType,
            name: metadata.name,
            size: metadata.size,
            updatedAt: created.createdAt,
          },
          target: libraryItems.documentId,
        });
      return created;
    });
  }

  async saveMessages(input: SaveMessageInput[]): Promise<void> {
    await this.db.insert(messages).values(input);
    const chatIds = [...new Set(input.map((message) => message.chatId))];
    await this.db
      .update(chats)
      .set({ updatedAt: new Date() })
      .where(inArray(chats.id, chatIds));
    const projectRows = await this.db
      .select({ projectId: chats.projectId })
      .from(chats)
      .where(inArray(chats.id, chatIds));
    const projectIds = [
      ...new Set(
        projectRows.flatMap((row) => (row.projectId ? [row.projectId] : [])),
      ),
    ];
    if (projectIds.length > 0) {
      await this.db
        .update(projects)
        .set({ updatedAt: new Date() })
        .where(inArray(projects.id, projectIds));
    }
  }

  async saveObjectFile(input: {
    contentType: string;
    pathname: string;
    size: number;
    url: string;
    userId: string;
  }): Promise<ObjectFileRow> {
    const [created] = await this.db
      .insert(objectFiles)
      .values(input)
      .returning();
    if (!created) {
      throw new Error('Object file creation returned no row');
    }
    return created;
  }

  async saveProject(ownerId: string, name: string): Promise<ProjectRow> {
    const [created] = await this.db
      .insert(projects)
      .values({ name, ownerId })
      .returning();
    if (!created) {
      throw new Error('Project creation returned no row');
    }
    return created;
  }

  async saveProjectSource(input: {
    contentType: string;
    extractedText: string;
    name: string;
    pathname: string;
    projectId: string;
    size: number;
    url: string;
    userId: string;
  }): Promise<ProjectSourceSummary> {
    return this.db.transaction(async (transaction) => {
      const [storedFile] = await transaction
        .insert(objectFiles)
        .values({
          contentType: input.contentType,
          pathname: input.pathname,
          size: input.size,
          url: input.url,
          userId: input.userId,
        })
        .returning();
      if (!storedFile) {
        throw new Error('Object file creation returned no row');
      }
      const [source] = await transaction
        .insert(projectSources)
        .values({
          contentType: input.contentType,
          extractedText: input.extractedText,
          name: input.name,
          objectFileId: storedFile.id,
          projectId: input.projectId,
          size: input.size,
        })
        .returning();
      if (!source) {
        throw new Error('Project source creation returned no row');
      }
      await transaction.insert(libraryItems).values({
        contentType: input.contentType,
        itemType: 'file',
        name: input.name,
        objectFileId: storedFile.id,
        ownerId: input.userId,
        size: input.size,
        source: 'uploaded',
      });
      await transaction
        .update(projects)
        .set({ updatedAt: new Date() })
        .where(eq(projects.id, input.projectId));
      const { extractedText: _, ...summary } = source;
      return summary;
    });
  }

  async saveSuggestions(input: SaveSuggestionInput[]): Promise<void> {
    await this.db.insert(suggestions).values(input);
  }

  async updateVisibility(
    chatId: string,
    visibility: ChatVisibility,
  ): Promise<void> {
    await this.db
      .update(chats)
      .set({ updatedAt: new Date(), visibility })
      .where(eq(chats.id, chatId));
  }

  async updateProject(id: string, name: string): Promise<ProjectRow> {
    const [updated] = await this.db
      .update(projects)
      .set({ name, updatedAt: new Date() })
      .where(eq(projects.id, id))
      .returning();
    if (!updated) {
      throw new Error('Project update returned no row');
    }
    return updated;
  }

  async vote(
    chatId: string,
    messageId: string,
    isUpvoted: boolean,
  ): Promise<void> {
    await this.db
      .insert(votes)
      .values({ chatId, isUpvoted, messageId })
      .onConflictDoUpdate({
        set: { isUpvoted, updatedAt: new Date() },
        target: [votes.chatId, votes.messageId],
      });
  }
}
