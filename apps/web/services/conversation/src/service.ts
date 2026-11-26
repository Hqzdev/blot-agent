import type {
  ArtifactKind,
  ChatVisibility,
  LibraryBulkInput,
  LibraryCreateFolderInput,
  LibraryCreateUploadInput,
  LibraryDownloadEntry,
  LibraryItem,
  LibraryListInput,
  LibraryListResult,
  LibraryUpdateItemInput,
  StoredMessage,
} from '@teya/contracts';
import type {
  ChatRow,
  ChatSummaryRow,
  DocumentRow,
  MessageRow,
  ObjectFileRow,
  ProjectRow,
  SuggestionRow,
  VoteRow,
} from '@teya/database';

import {
  ConversationForbiddenError,
  ConversationNotFoundError,
  ConversationValidationError,
} from './errors';
import { LibraryService } from './library-service';
import { ProjectContextBuilder } from './project-context';
import type {
  ConversationRepository,
  ProjectSourceSummary,
  ProjectSummary,
  SaveSuggestionInput,
} from './repository';

export class ConversationService {
  private readonly libraryService: LibraryService;

  constructor(
    private readonly repository: ConversationRepository,
    private readonly contextBuilder = new ProjectContextBuilder(),
    libraryService?: LibraryService,
  ) {
    this.libraryService = libraryService ?? new LibraryService(repository);
  }

  getChats(actorId: string): Promise<ChatSummaryRow[]> {
    return this.repository.findChats(actorId);
  }

  async getChat(actorId: string, id: string): Promise<ChatRow | null> {
    const chat = await this.repository.findChat(id);
    if (!chat) {
      return null;
    }
    if (
      chat.userId !== actorId &&
      (chat.visibility !== 'public' || chat.projectId)
    ) {
      throw new ConversationForbiddenError('Chat access is forbidden');
    }
    return chat;
  }

  async saveChat(
    actorId: string,
    id: string,
    title: string,
    projectId?: string,
  ): Promise<ChatRow> {
    const existing = await this.repository.findChat(id);
    if (existing) {
      if (existing.userId !== actorId) {
        throw new ConversationForbiddenError('Chat access is forbidden');
      }
      if (existing.projectId !== (projectId ?? null)) {
        throw new ConversationForbiddenError(
          'Chat does not belong to this project',
        );
      }
      return existing;
    }
    if (projectId) {
      await this.requireOwnedProject(actorId, projectId);
    }
    return this.repository.saveChat(id, actorId, title, projectId);
  }

  getProjects(actorId: string, query?: string): Promise<ProjectSummary[]> {
    return this.repository.findProjects(actorId, query?.trim() || undefined);
  }

  async getProject(actorId: string, id: string): Promise<ProjectRow> {
    return this.requireOwnedProject(actorId, id);
  }

  createProject(actorId: string, name: string): Promise<ProjectRow> {
    return this.repository.saveProject(actorId, name.trim());
  }

  async updateProject(
    actorId: string,
    id: string,
    name: string,
  ): Promise<ProjectRow> {
    await this.requireOwnedProject(actorId, id);
    return this.repository.updateProject(id, name.trim());
  }

  async deleteProject(actorId: string, id: string): Promise<string[]> {
    await this.requireOwnedProject(actorId, id);
    return this.repository.deleteProject(id);
  }

  async getProjectChats(
    actorId: string,
    projectId: string,
  ): Promise<ChatSummaryRow[]> {
    await this.requireOwnedProject(actorId, projectId);
    return this.repository.findProjectChats(projectId);
  }

  async getProjectSources(
    actorId: string,
    projectId: string,
  ): Promise<ProjectSourceSummary[]> {
    await this.requireOwnedProject(actorId, projectId);
    return this.repository.findProjectSources(projectId);
  }

  async saveProjectSource(
    actorId: string,
    input: {
      contentType: string;
      extractedText: string;
      name: string;
      pathname: string;
      projectId: string;
      size: number;
      url: string;
    },
  ): Promise<ProjectSourceSummary> {
    await this.requireOwnedProject(actorId, input.projectId);
    const sources = await this.repository.findProjectSources(input.projectId);
    if (sources.length >= 20) {
      throw new ConversationValidationError(
        'A project can contain up to 20 sources',
      );
    }
    return this.repository.saveProjectSource({ ...input, userId: actorId });
  }

  async deleteProjectSource(
    actorId: string,
    projectId: string,
    sourceId: string,
  ): Promise<string> {
    await this.requireOwnedProject(actorId, projectId);
    const source = await this.repository.findProjectSource(sourceId);
    if (!source || source.projectId !== projectId) {
      throw new ConversationNotFoundError('Project source not found');
    }
    return this.repository.deleteProjectSource(sourceId);
  }

  async getProjectContext(
    actorId: string,
    projectId: string,
    currentChatId: string,
  ): Promise<string> {
    await this.requireOwnedProject(actorId, projectId);
    const [messages, sources] = await Promise.all([
      this.repository.findProjectContextMessages(projectId, currentChatId),
      this.repository.findProjectContextSources(projectId),
    ]);
    return this.contextBuilder.build(messages, sources);
  }

  async deleteChat(actorId: string, id: string): Promise<void> {
    await this.requireOwnedChat(actorId, id);
    await this.repository.deleteChat(id);
  }

  async getMessages(actorId: string, chatId: string): Promise<MessageRow[]> {
    const chat = await this.requireReadableChat(actorId, chatId);
    const [storedMessages, libraryRows] = await Promise.all([
      this.repository.findMessages(chatId),
      this.repository.findLibraryItems(chat.userId),
    ]);
    const byId = new Map(libraryRows.map((item) => [item.id, item]));
    const byUrl = new Map(
      libraryRows.flatMap((item) => (item.url ? [[item.url, item]] : [])),
    );
    return storedMessages.map((message) => ({
      ...message,
      attachments: message.attachments.map((attachment) => {
        if (!this.isRecord(attachment)) {
          return attachment;
        }
        const libraryItem =
          (typeof attachment.libraryItemId === 'string'
            ? byId.get(attachment.libraryItemId)
            : undefined) ??
          (typeof attachment.url === 'string'
            ? byUrl.get(attachment.url)
            : undefined);
        if (!libraryItem) {
          return attachment;
        }
        return {
          ...attachment,
          deleted: Boolean(libraryItem.deletedAt),
          libraryItemId: libraryItem.id,
          name: libraryItem.name,
        };
      }),
    }));
  }

  getObjectFiles(actorId: string): Promise<ObjectFileRow[]> {
    return this.repository.findObjectFiles(actorId);
  }

  async saveMessages(actorId: string, input: StoredMessage[]): Promise<void> {
    const chatIds = [...new Set(input.map((message) => message.chatId))];
    await Promise.all(
      chatIds.map((chatId) => this.requireOwnedChat(actorId, chatId)),
    );
    await this.repository.saveMessages(
      input.map((message) => ({
        ...message,
        attachments: message.attachments ?? [],
        parts:
          message.parts.length > 0
            ? message.parts
            : [{ type: 'text', text: '' }],
      })),
    );
  }

  saveObjectFile(
    actorId: string,
    input: {
      contentType: string;
      pathname: string;
      size: number;
      url: string;
    },
  ): Promise<ObjectFileRow> {
    return this.repository.saveObjectFile({ ...input, userId: actorId });
  }

  async getVotes(actorId: string, chatId: string): Promise<VoteRow[]> {
    await this.requireOwnedChat(actorId, chatId);
    return this.repository.findVotes(chatId);
  }

  async vote(
    actorId: string,
    chatId: string,
    messageId: string,
    type: 'up' | 'down',
  ): Promise<void> {
    await this.requireOwnedChat(actorId, chatId);
    const message = await this.repository.findMessage(messageId);
    if (!message || message.chatId !== chatId) {
      throw new ConversationNotFoundError('Message not found');
    }
    await this.repository.vote(chatId, messageId, type === 'up');
  }

  async getDocument(actorId: string, id: string): Promise<DocumentRow> {
    const document = await this.repository.findDocument(id);
    this.requireOwnedDocument(actorId, document);
    if (!(await this.libraryService.isDocumentAvailable(actorId, id))) {
      throw new ConversationNotFoundError('Document has been deleted');
    }
    return document;
  }

  async getDocuments(actorId: string, id: string): Promise<DocumentRow[]> {
    const documents = await this.repository.findDocuments(id);
    this.requireOwnedDocument(actorId, documents[0]);
    if (!(await this.libraryService.isDocumentAvailable(actorId, id))) {
      throw new ConversationNotFoundError('Document has been deleted');
    }
    return documents;
  }

  saveDocument(
    actorId: string,
    input: {
      content: string;
      id: string;
      kind: ArtifactKind;
      title: string;
    },
  ): Promise<DocumentRow> {
    return this.repository.saveDocument({ ...input, userId: actorId });
  }

  async deleteDocumentsAfter(
    actorId: string,
    id: string,
    timestamp: Date,
  ): Promise<void> {
    await this.getDocument(actorId, id);
    await this.repository.deleteDocumentsAfter(id, timestamp);
  }

  async getSuggestions(
    actorId: string,
    documentId: string,
  ): Promise<SuggestionRow[]> {
    await this.getDocument(actorId, documentId);
    return this.repository.findSuggestions(documentId);
  }

  async saveSuggestions(
    actorId: string,
    input: Omit<SaveSuggestionInput, 'userId'>[],
  ): Promise<void> {
    const documentIds = [
      ...new Set(input.map((suggestion) => suggestion.documentId)),
    ];
    await Promise.all(
      documentIds.map((documentId) => this.getDocument(actorId, documentId)),
    );
    await this.repository.saveSuggestions(
      input.map((suggestion) => ({ ...suggestion, userId: actorId })),
    );
  }

  async getMessage(actorId: string, id: string): Promise<MessageRow> {
    const message = await this.repository.findMessage(id);
    if (!message) {
      throw new ConversationNotFoundError('Message not found');
    }
    await this.requireOwnedChat(actorId, message.chatId);
    return message;
  }

  async deleteMessagesAfter(
    actorId: string,
    chatId: string,
    timestamp: Date,
  ): Promise<void> {
    await this.requireOwnedChat(actorId, chatId);
    await this.repository.deleteMessagesAfter(chatId, timestamp);
  }

  async updateVisibility(
    actorId: string,
    chatId: string,
    visibility: ChatVisibility,
  ): Promise<void> {
    const chat = await this.requireOwnedChat(actorId, chatId);
    if (chat.projectId && visibility === 'public') {
      throw new ConversationForbiddenError(
        'Project chats cannot be made public',
      );
    }
    await this.repository.updateVisibility(chatId, visibility);
  }

  deleteUserData(userId: string): Promise<void> {
    return this.repository.deleteUserData(userId);
  }

  listLibraryItems(
    actorId: string,
    input: LibraryListInput,
  ): Promise<LibraryListResult> {
    return this.libraryService.list(actorId, input);
  }

  getLibraryItem(actorId: string, id: string): Promise<LibraryItem> {
    return this.libraryService.get(actorId, id);
  }

  createLibraryFolder(
    actorId: string,
    input: LibraryCreateFolderInput,
  ): Promise<LibraryItem> {
    return this.libraryService.createFolder(actorId, input);
  }

  createLibraryUpload(
    actorId: string,
    input: LibraryCreateUploadInput,
  ): Promise<LibraryItem> {
    return this.libraryService.createUpload(actorId, input);
  }

  updateLibraryItem(
    actorId: string,
    id: string,
    input: LibraryUpdateItemInput,
  ): Promise<LibraryItem> {
    return this.libraryService.update(actorId, id, input);
  }

  trashLibraryItems(actorId: string, ids: string[]): Promise<void> {
    return this.libraryService.trash(actorId, ids);
  }

  restoreLibraryItems(actorId: string, ids: string[]): Promise<void> {
    return this.libraryService.restore(actorId, ids);
  }

  permanentlyDeleteLibraryItems(
    actorId: string,
    ids: string[],
  ): Promise<string[]> {
    return this.libraryService.permanentlyDelete(actorId, ids);
  }

  bulkLibraryItems(
    actorId: string,
    input: LibraryBulkInput,
  ): Promise<string[]> {
    return this.libraryService.bulk(actorId, input);
  }

  getLibraryDownloadManifest(
    actorId: string,
    ids: string[],
  ): Promise<LibraryDownloadEntry[]> {
    return this.libraryService.getDownloadManifest(actorId, ids);
  }

  getExpiredLibraryItems(now: Date): Promise<string[]> {
    return this.libraryService.getExpiredRootIds(now);
  }

  purgeExpiredLibraryItems(ids: string[]): Promise<string[]> {
    return this.repository.deleteLibraryItems(ids);
  }

  private async requireReadableChat(
    actorId: string,
    id: string,
  ): Promise<ChatRow> {
    const chat = await this.repository.findChat(id);
    if (!chat) {
      throw new ConversationNotFoundError('Chat not found');
    }
    if (
      chat.userId !== actorId &&
      (chat.visibility !== 'public' || chat.projectId)
    ) {
      throw new ConversationForbiddenError('Chat access is forbidden');
    }
    return chat;
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
  }

  private async requireOwnedChat(
    actorId: string,
    id: string,
  ): Promise<ChatRow> {
    const chat = await this.repository.findChat(id);
    if (!chat) {
      throw new ConversationNotFoundError('Chat not found');
    }
    if (chat.userId !== actorId) {
      throw new ConversationForbiddenError('Chat access is forbidden');
    }
    return chat;
  }

  private requireOwnedDocument(
    actorId: string,
    document: DocumentRow | undefined,
  ): asserts document is DocumentRow {
    if (!document) {
      throw new ConversationNotFoundError('Document not found');
    }
    if (document.userId !== actorId) {
      throw new ConversationForbiddenError('Document access is forbidden');
    }
  }

  private async requireOwnedProject(
    actorId: string,
    id: string,
  ): Promise<ProjectRow> {
    const project = await this.repository.findProject(id);
    if (!project) {
      throw new ConversationNotFoundError('Project not found');
    }
    if (project.ownerId !== actorId) {
      throw new ConversationForbiddenError('Project access is forbidden');
    }
    return project;
  }
}
