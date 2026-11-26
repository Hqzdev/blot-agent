import 'server-only';
import { ChatSynchronizer } from './chat-synchronizer';

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
import { InternalApiClient } from '@teya/platform';
import {
  ConversationService,
  PostgresConversationRepository,
  type ProjectSourceSummary,
  type ProjectSummary,
  type SaveSuggestionInput,
} from '@teya/service-conversation';

interface RpcResponse<T> {
  result: T;
}

export interface ConversationGateway {
  bulkLibraryItems(actorId: string, input: LibraryBulkInput): Promise<string[]>;
  createLibraryFolder(
    actorId: string,
    input: LibraryCreateFolderInput,
  ): Promise<LibraryItem>;
  createLibraryUpload(
    actorId: string,
    input: LibraryCreateUploadInput,
  ): Promise<LibraryItem>;
  deleteChat(actorId: string, id: string): Promise<void>;
  deleteProject(actorId: string, id: string): Promise<string[]>;
  deleteProjectSource(
    actorId: string,
    projectId: string,
    sourceId: string,
  ): Promise<string>;
  deleteDocumentsAfter(
    actorId: string,
    id: string,
    timestamp: Date,
  ): Promise<void>;
  deleteMessagesAfter(
    actorId: string,
    chatId: string,
    timestamp: Date,
  ): Promise<void>;
  deleteUserData(userId: string): Promise<void>;
  getChat(actorId: string, id: string): Promise<ChatRow | null>;
  getChats(actorId: string): Promise<ChatSummaryRow[]>;
  getDocument(actorId: string, id: string): Promise<DocumentRow>;
  getDocuments(actorId: string, id: string): Promise<DocumentRow[]>;
  getMessage(actorId: string, id: string): Promise<MessageRow>;
  getMessages(actorId: string, chatId: string): Promise<MessageRow[]>;
  getExpiredLibraryItems(now: Date): Promise<string[]>;
  getLibraryDownloadManifest(
    actorId: string,
    ids: string[],
  ): Promise<LibraryDownloadEntry[]>;
  getLibraryItem(actorId: string, id: string): Promise<LibraryItem>;
  getObjectFiles(actorId: string): Promise<ObjectFileRow[]>;
  getProject(actorId: string, id: string): Promise<ProjectRow>;
  getProjectChats(
    actorId: string,
    projectId: string,
  ): Promise<ChatSummaryRow[]>;
  getProjectContext(
    actorId: string,
    projectId: string,
    currentChatId: string,
  ): Promise<string>;
  getProjects(actorId: string, query?: string): Promise<ProjectSummary[]>;
  getProjectSources(
    actorId: string,
    projectId: string,
  ): Promise<ProjectSourceSummary[]>;
  getSuggestions(actorId: string, documentId: string): Promise<SuggestionRow[]>;
  getVotes(actorId: string, chatId: string): Promise<VoteRow[]>;
  listLibraryItems(
    actorId: string,
    input: LibraryListInput,
  ): Promise<LibraryListResult>;
  permanentlyDeleteLibraryItems(
    actorId: string,
    ids: string[],
  ): Promise<string[]>;
  purgeExpiredLibraryItems(ids: string[]): Promise<string[]>;
  restoreLibraryItems(actorId: string, ids: string[]): Promise<void>;
  saveChat(
    actorId: string,
    id: string,
    title: string,
    projectId?: string,
  ): Promise<ChatRow>;
  createProject(actorId: string, name: string): Promise<ProjectRow>;
  saveDocument(
    actorId: string,
    input: {
      content: string;
      id: string;
      kind: ArtifactKind;
      title: string;
    },
  ): Promise<DocumentRow>;
  saveMessages(actorId: string, messages: StoredMessage[]): Promise<void>;
  saveObjectFile(
    actorId: string,
    input: {
      contentType: string;
      pathname: string;
      size: number;
      url: string;
    },
  ): Promise<ObjectFileRow>;
  saveProjectSource(
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
  ): Promise<ProjectSourceSummary>;
  saveSuggestions(
    actorId: string,
    suggestions: Omit<SaveSuggestionInput, 'userId'>[],
  ): Promise<void>;
  trashLibraryItems(actorId: string, ids: string[]): Promise<void>;
  updateLibraryItem(
    actorId: string,
    id: string,
    input: LibraryUpdateItemInput,
  ): Promise<LibraryItem>;
  updateVisibility(
    actorId: string,
    chatId: string,
    visibility: ChatVisibility,
  ): Promise<void>;
  updateProject(actorId: string, id: string, name: string): Promise<ProjectRow>;
  vote(
    actorId: string,
    chatId: string,
    messageId: string,
    type: 'up' | 'down',
  ): Promise<void>;
}

class LocalConversationGateway implements ConversationGateway {
  private readonly sync = new ChatSynchronizer();
  private readonly service = new ConversationService(
    new PostgresConversationRepository(),
  );

  bulkLibraryItems(actorId: string, input: LibraryBulkInput) {
    return this.service.bulkLibraryItems(actorId, input);
  }

  createLibraryFolder(actorId: string, input: LibraryCreateFolderInput) {
    return this.service.createLibraryFolder(actorId, input);
  }

  createLibraryUpload(actorId: string, input: LibraryCreateUploadInput) {
    return this.service.createLibraryUpload(actorId, input);
  }

  async deleteChat(actorId: string, id: string) {
    await this.service.deleteChat(actorId, id);
    await this.sync.synchronize(actorId);
  }

  deleteProject(actorId: string, id: string) {
    return this.service.deleteProject(actorId, id);
  }

  deleteProjectSource(actorId: string, projectId: string, sourceId: string) {
    return this.service.deleteProjectSource(actorId, projectId, sourceId);
  }

  deleteDocumentsAfter(actorId: string, id: string, timestamp: Date) {
    return this.service.deleteDocumentsAfter(actorId, id, timestamp);
  }

  async deleteMessagesAfter(actorId: string, chatId: string, timestamp: Date) {
    await this.service.deleteMessagesAfter(actorId, chatId, timestamp);
    await this.sync.synchronize(actorId);
  }

  deleteUserData(userId: string) {
    return this.service.deleteUserData(userId);
  }

  async getChat(actorId: string, id: string) {
    if (!actorId.startsWith('anonymous:')) await this.sync.synchronize(actorId);
    return this.service.getChat(actorId, id);
  }

  async getChats(actorId: string) {
    await this.sync.synchronize(actorId);
    return this.service.getChats(actorId);
  }

  getDocument(actorId: string, id: string) {
    return this.service.getDocument(actorId, id);
  }

  getDocuments(actorId: string, id: string) {
    return this.service.getDocuments(actorId, id);
  }

  getMessage(actorId: string, id: string) {
    return this.service.getMessage(actorId, id);
  }

  async getMessages(actorId: string, chatId: string) {
    if (!actorId.startsWith('anonymous:')) await this.sync.synchronize(actorId);
    return this.service.getMessages(actorId, chatId);
  }

  getExpiredLibraryItems(now: Date) {
    return this.service.getExpiredLibraryItems(now);
  }

  getLibraryDownloadManifest(actorId: string, ids: string[]) {
    return this.service.getLibraryDownloadManifest(actorId, ids);
  }

  getLibraryItem(actorId: string, id: string) {
    return this.service.getLibraryItem(actorId, id);
  }

  getObjectFiles(actorId: string) {
    return this.service.getObjectFiles(actorId);
  }

  getProject(actorId: string, id: string) {
    return this.service.getProject(actorId, id);
  }

  getProjectChats(actorId: string, projectId: string) {
    return this.service.getProjectChats(actorId, projectId);
  }

  getProjectContext(actorId: string, projectId: string, currentChatId: string) {
    return this.service.getProjectContext(actorId, projectId, currentChatId);
  }

  getProjects(actorId: string, query?: string) {
    return this.service.getProjects(actorId, query);
  }

  getProjectSources(actorId: string, projectId: string) {
    return this.service.getProjectSources(actorId, projectId);
  }

  getSuggestions(actorId: string, documentId: string) {
    return this.service.getSuggestions(actorId, documentId);
  }

  getVotes(actorId: string, chatId: string) {
    return this.service.getVotes(actorId, chatId);
  }

  listLibraryItems(actorId: string, input: LibraryListInput) {
    return this.service.listLibraryItems(actorId, input);
  }

  permanentlyDeleteLibraryItems(actorId: string, ids: string[]) {
    return this.service.permanentlyDeleteLibraryItems(actorId, ids);
  }

  purgeExpiredLibraryItems(ids: string[]) {
    return this.service.purgeExpiredLibraryItems(ids);
  }

  restoreLibraryItems(actorId: string, ids: string[]) {
    return this.service.restoreLibraryItems(actorId, ids);
  }

  async saveChat(
    actorId: string,
    id: string,
    title: string,
    projectId?: string,
  ) {
    const chat = await this.service.saveChat(actorId, id, title, projectId);
    await this.sync.synchronize(actorId);
    return chat;
  }

  createProject(actorId: string, name: string) {
    return this.service.createProject(actorId, name);
  }

  saveDocument(
    actorId: string,
    input: {
      content: string;
      id: string;
      kind: ArtifactKind;
      title: string;
    },
  ) {
    return this.service.saveDocument(actorId, input);
  }

  async saveMessages(actorId: string, messages: StoredMessage[]) {
    await this.service.saveMessages(actorId, messages);
    await this.sync.synchronize(actorId);
  }

  saveObjectFile(
    actorId: string,
    input: {
      contentType: string;
      pathname: string;
      size: number;
      url: string;
    },
  ) {
    return this.service.saveObjectFile(actorId, input);
  }

  saveProjectSource(
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
  ) {
    return this.service.saveProjectSource(actorId, input);
  }

  saveSuggestions(
    actorId: string,
    suggestions: Omit<SaveSuggestionInput, 'userId'>[],
  ) {
    return this.service.saveSuggestions(actorId, suggestions);
  }

  trashLibraryItems(actorId: string, ids: string[]) {
    return this.service.trashLibraryItems(actorId, ids);
  }

  updateLibraryItem(
    actorId: string,
    id: string,
    input: LibraryUpdateItemInput,
  ) {
    return this.service.updateLibraryItem(actorId, id, input);
  }

  updateVisibility(
    actorId: string,
    chatId: string,
    visibility: ChatVisibility,
  ) {
    return this.service.updateVisibility(actorId, chatId, visibility);
  }

  updateProject(actorId: string, id: string, name: string) {
    return this.service.updateProject(actorId, id, name);
  }

  vote(
    actorId: string,
    chatId: string,
    messageId: string,
    type: 'up' | 'down',
  ) {
    return this.service.vote(actorId, chatId, messageId, type);
  }
}

class HttpConversationGateway implements ConversationGateway {
  private readonly client: InternalApiClient;

  constructor(baseUrl: string, secret: string) {
    this.client = new InternalApiClient(baseUrl, secret);
  }

  bulkLibraryItems(
    actorId: string,
    input: LibraryBulkInput,
  ): Promise<string[]> {
    return this.call(actorId, {
      operation: 'bulkLibraryItems',
      payload: input,
    });
  }

  async createLibraryFolder(
    actorId: string,
    input: LibraryCreateFolderInput,
  ): Promise<LibraryItem> {
    return this.reviveLibraryItem(
      await this.call(actorId, {
        operation: 'createLibraryFolder',
        payload: input,
      }),
    );
  }

  async createLibraryUpload(
    actorId: string,
    input: LibraryCreateUploadInput,
  ): Promise<LibraryItem> {
    return this.reviveLibraryItem(
      await this.call(actorId, {
        operation: 'createLibraryUpload',
        payload: input,
      }),
    );
  }

  async deleteChat(actorId: string, id: string): Promise<void> {
    await this.call(actorId, {
      operation: 'deleteChat',
      payload: { id },
    });
  }

  deleteProject(actorId: string, id: string): Promise<string[]> {
    return this.call(actorId, {
      operation: 'deleteProject',
      payload: { id },
    });
  }

  deleteProjectSource(
    actorId: string,
    projectId: string,
    sourceId: string,
  ): Promise<string> {
    return this.call(actorId, {
      operation: 'deleteProjectSource',
      payload: { projectId, sourceId },
    });
  }

  async deleteDocumentsAfter(
    actorId: string,
    id: string,
    timestamp: Date,
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'deleteDocumentsAfter',
      payload: { id, timestamp },
    });
  }

  async deleteMessagesAfter(
    actorId: string,
    chatId: string,
    timestamp: Date,
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'deleteMessagesAfter',
      payload: { chatId, timestamp },
    });
  }

  async deleteUserData(userId: string): Promise<void> {
    await this.call('system:web', {
      operation: 'deleteUserData',
      payload: { userId },
    });
  }

  async getChat(actorId: string, id: string): Promise<ChatRow | null> {
    const row = await this.call<ChatRow | null>(actorId, {
      operation: 'getChat',
      payload: { id },
    });
    return row ? this.reviveChat(row) : null;
  }

  async getChats(actorId: string): Promise<ChatSummaryRow[]> {
    const rows = await this.call<ChatSummaryRow[]>(actorId, {
      operation: 'getChats',
      payload: {},
    });
    return rows.map((row) => this.reviveChatSummary(row));
  }

  async getDocument(actorId: string, id: string): Promise<DocumentRow> {
    return this.reviveDocument(
      await this.call(actorId, {
        operation: 'getDocument',
        payload: { id },
      }),
    );
  }

  async getDocuments(actorId: string, id: string): Promise<DocumentRow[]> {
    const rows = await this.call<DocumentRow[]>(actorId, {
      operation: 'getDocuments',
      payload: { id },
    });
    return rows.map((row) => this.reviveDocument(row));
  }

  async getMessage(actorId: string, id: string): Promise<MessageRow> {
    return this.reviveMessage(
      await this.call(actorId, {
        operation: 'getMessage',
        payload: { id },
      }),
    );
  }

  async getMessages(actorId: string, chatId: string): Promise<MessageRow[]> {
    const rows = await this.call<MessageRow[]>(actorId, {
      operation: 'getMessages',
      payload: { chatId },
    });
    return rows.map((row) => this.reviveMessage(row));
  }

  getExpiredLibraryItems(now: Date): Promise<string[]> {
    return this.call('system:web', {
      operation: 'getExpiredLibraryItems',
      payload: { now },
    });
  }

  getLibraryDownloadManifest(
    actorId: string,
    ids: string[],
  ): Promise<LibraryDownloadEntry[]> {
    return this.call(actorId, {
      operation: 'getLibraryDownloadManifest',
      payload: { ids },
    });
  }

  async getLibraryItem(actorId: string, id: string): Promise<LibraryItem> {
    return this.reviveLibraryItem(
      await this.call(actorId, {
        operation: 'getLibraryItem',
        payload: { id },
      }),
    );
  }

  async getObjectFiles(actorId: string): Promise<ObjectFileRow[]> {
    const rows = await this.call<ObjectFileRow[]>(actorId, {
      operation: 'getObjectFiles',
      payload: {},
    });
    return rows.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
    }));
  }

  async getProject(actorId: string, id: string): Promise<ProjectRow> {
    return this.reviveProject(
      await this.call(actorId, {
        operation: 'getProject',
        payload: { id },
      }),
    );
  }

  async getProjectChats(
    actorId: string,
    projectId: string,
  ): Promise<ChatSummaryRow[]> {
    const rows = await this.call<ChatSummaryRow[]>(actorId, {
      operation: 'getProjectChats',
      payload: { projectId },
    });
    return rows.map((row) => this.reviveChatSummary(row));
  }

  getProjectContext(
    actorId: string,
    projectId: string,
    currentChatId: string,
  ): Promise<string> {
    return this.call(actorId, {
      operation: 'getProjectContext',
      payload: { currentChatId, projectId },
    });
  }

  async getProjects(
    actorId: string,
    query?: string,
  ): Promise<ProjectSummary[]> {
    const rows = await this.call<ProjectSummary[]>(actorId, {
      operation: 'getProjects',
      payload: { query },
    });
    return rows.map((row) => ({
      ...this.reviveProject(row),
      chatCount: row.chatCount,
      sourceCount: row.sourceCount,
    }));
  }

  async getProjectSources(
    actorId: string,
    projectId: string,
  ): Promise<ProjectSourceSummary[]> {
    const rows = await this.call<ProjectSourceSummary[]>(actorId, {
      operation: 'getProjectSources',
      payload: { projectId },
    });
    return rows.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  async getSuggestions(
    actorId: string,
    documentId: string,
  ): Promise<SuggestionRow[]> {
    const rows = await this.call<SuggestionRow[]>(actorId, {
      operation: 'getSuggestions',
      payload: { documentId },
    });
    return rows.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      documentCreatedAt: new Date(row.documentCreatedAt),
    }));
  }

  getVotes(actorId: string, chatId: string): Promise<VoteRow[]> {
    return this.call(actorId, {
      operation: 'getVotes',
      payload: { chatId },
    });
  }

  async listLibraryItems(
    actorId: string,
    input: LibraryListInput,
  ): Promise<LibraryListResult> {
    const result = await this.call<LibraryListResult>(actorId, {
      operation: 'listLibraryItems',
      payload: input,
    });
    return {
      ...result,
      items: result.items.map((item) => this.reviveLibraryItem(item)),
    };
  }

  permanentlyDeleteLibraryItems(
    actorId: string,
    ids: string[],
  ): Promise<string[]> {
    return this.call(actorId, {
      operation: 'permanentlyDeleteLibraryItems',
      payload: { ids },
    });
  }

  purgeExpiredLibraryItems(ids: string[]): Promise<string[]> {
    return this.call('system:web', {
      operation: 'purgeExpiredLibraryItems',
      payload: { ids },
    });
  }

  async restoreLibraryItems(actorId: string, ids: string[]): Promise<void> {
    await this.call(actorId, {
      operation: 'restoreLibraryItems',
      payload: { ids },
    });
  }

  async saveChat(
    actorId: string,
    id: string,
    title: string,
    projectId?: string,
  ): Promise<ChatRow> {
    return this.reviveChat(
      await this.call(actorId, {
        operation: 'saveChat',
        payload: { id, projectId, title },
      }),
    );
  }

  async createProject(actorId: string, name: string): Promise<ProjectRow> {
    return this.reviveProject(
      await this.call(actorId, {
        operation: 'createProject',
        payload: { name },
      }),
    );
  }

  async saveDocument(
    actorId: string,
    input: {
      content: string;
      id: string;
      kind: ArtifactKind;
      title: string;
    },
  ): Promise<DocumentRow> {
    return this.reviveDocument(
      await this.call(actorId, {
        operation: 'saveDocument',
        payload: input,
      }),
    );
  }

  async saveMessages(
    actorId: string,
    messages: StoredMessage[],
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'saveMessages',
      payload: { messages },
    });
  }

  async saveObjectFile(
    actorId: string,
    input: {
      contentType: string;
      pathname: string;
      size: number;
      url: string;
    },
  ): Promise<ObjectFileRow> {
    const row = await this.call<ObjectFileRow>(actorId, {
      operation: 'saveObjectFile',
      payload: input,
    });
    return {
      ...row,
      createdAt: new Date(row.createdAt),
    };
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
    const row = await this.call<ProjectSourceSummary>(actorId, {
      operation: 'saveProjectSource',
      payload: input,
    });
    return {
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    };
  }

  async saveSuggestions(
    actorId: string,
    suggestions: Omit<SaveSuggestionInput, 'userId'>[],
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'saveSuggestions',
      payload: { suggestions },
    });
  }

  async trashLibraryItems(actorId: string, ids: string[]): Promise<void> {
    await this.call(actorId, {
      operation: 'trashLibraryItems',
      payload: { ids },
    });
  }

  async updateLibraryItem(
    actorId: string,
    id: string,
    input: LibraryUpdateItemInput,
  ): Promise<LibraryItem> {
    return this.reviveLibraryItem(
      await this.call(actorId, {
        operation: 'updateLibraryItem',
        payload: { id, ...input },
      }),
    );
  }

  async updateVisibility(
    actorId: string,
    chatId: string,
    visibility: ChatVisibility,
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'updateVisibility',
      payload: { chatId, visibility },
    });
  }

  async updateProject(
    actorId: string,
    id: string,
    name: string,
  ): Promise<ProjectRow> {
    return this.reviveProject(
      await this.call(actorId, {
        operation: 'updateProject',
        payload: { id, name },
      }),
    );
  }

  async vote(
    actorId: string,
    chatId: string,
    messageId: string,
    type: 'up' | 'down',
  ): Promise<void> {
    await this.call(actorId, {
      operation: 'vote',
      payload: { chatId, messageId, type },
    });
  }

  private async call<T>(actorId: string, body: unknown): Promise<T> {
    const response = await this.client.request<RpcResponse<T>>({
      actorId,
      body,
      path: '/api/rpc',
    });
    return response.result;
  }

  private reviveChat(row: ChatRow): ChatRow {
    return {
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    };
  }

  private reviveChatSummary(row: ChatSummaryRow): ChatSummaryRow {
    return {
      ...this.reviveChat(row),
      projectName: row.projectName,
    };
  }

  private reviveDocument(row: DocumentRow): DocumentRow {
    return {
      ...row,
      createdAt: new Date(row.createdAt),
    };
  }

  private reviveMessage(row: MessageRow): MessageRow {
    return {
      ...row,
      createdAt: new Date(row.createdAt),
    };
  }

  private reviveProject(row: ProjectRow): ProjectRow {
    return {
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    };
  }

  private reviveLibraryItem(item: LibraryItem): LibraryItem {
    return {
      ...item,
      createdAt: new Date(item.createdAt),
      deletedAt: item.deletedAt ? new Date(item.deletedAt) : null,
      purgeAfter: item.purgeAfter ? new Date(item.purgeAfter) : null,
      updatedAt: new Date(item.updatedAt),
    };
  }
}

let conversationGateway: ConversationGateway | undefined;

export function getConversationGateway(): ConversationGateway {
  if (conversationGateway) {
    return conversationGateway;
  }
  const serviceUrl = process.env.CONVERSATION_SERVICE_URL;
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  conversationGateway =
    serviceUrl && secret
      ? new HttpConversationGateway(serviceUrl, secret)
      : new LocalConversationGateway();
  return conversationGateway;
}
