import assert from 'node:assert/strict';
import test from 'node:test';

import type {
  ArtifactKind,
  ChatVisibility,
  LibraryCreateUploadInput,
} from '@teya/contracts';
import type {
  ChatRow,
  ChatSummaryRow,
  DocumentRow,
  MessageRow,
  ObjectFileRow,
  ProjectRow,
  ProjectSourceRow,
  SuggestionRow,
  VoteRow,
} from '@teya/database';
import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  type ConversationRepository,
  ConversationRpcController,
  ConversationService,
  type LibraryDownloadRecord,
  type LibraryItemRecord,
  type ProjectContextMessage,
  type ProjectContextSource,
  type ProjectSourceSummary,
  type ProjectSummary,
  type SaveMessageInput,
  type SaveSuggestionInput,
} from '@teya/service-conversation';

const secret = 'a-secure-internal-secret-with-32-characters';
const ownerId = '11111111-1111-4111-8111-111111111111';
const attackerId = '22222222-2222-4222-8222-222222222222';
const privateChatId = '33333333-3333-4333-8333-333333333333';
const publicChatId = '44444444-4444-4444-8444-444444444444';
const messageId = '55555555-5555-4555-8555-555555555555';
const projectId = '77777777-7777-4777-8777-777777777777';

class ConversationRepositoryFake implements ConversationRepository {
  readonly chats = new Map<string, ChatRow>([
    [privateChatId, this.createChat(privateChatId, 'private')],
    [publicChatId, this.createChat(publicChatId, 'public')],
  ]);
  readonly messages = new Map<string, MessageRow>();
  readonly projects = new Map<string, ProjectRow>([
    [
      projectId,
      {
        createdAt: new Date(),
        id: projectId,
        memoryMode: 'project_only',
        name: 'Owner project',
        ownerId,
        updatedAt: new Date(),
      },
    ],
  ]);
  readonly sources = new Map<string, ProjectSourceRow>();
  readonly libraryItems = new Map<string, LibraryItemRecord>();

  async createLibraryFolder(input: {
    name: string;
    ownerId: string;
    parentId: string | null;
  }): Promise<LibraryItemRecord> {
    const item = this.createLibraryItem({
      id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      itemType: 'folder',
      name: input.name,
      ownerId: input.ownerId,
      parentId: input.parentId,
      source: 'created',
    });
    this.libraryItems.set(item.id, item);
    return item;
  }

  async createLibraryUpload(
    input: LibraryCreateUploadInput & {
      ownerId: string;
      parentId: string | null;
    },
  ): Promise<LibraryItemRecord> {
    const item = this.createLibraryItem({
      contentType: input.contentType,
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      itemType: 'file',
      name: input.name,
      objectFileId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      ownerId: input.ownerId,
      parentId: input.parentId,
      size: input.size,
      source: 'uploaded',
      url: input.url,
    });
    this.libraryItems.set(item.id, item);
    return item;
  }

  async deleteLibraryItems(ids: string[]): Promise<string[]> {
    for (const id of ids) {
      this.libraryItems.delete(id);
    }
    return [];
  }

  async findExpiredLibraryRootIds(): Promise<string[]> {
    return [];
  }

  async findLibraryDownloadRecords(
    ids: string[],
  ): Promise<LibraryDownloadRecord[]> {
    return ids.flatMap((id) => {
      const item = this.libraryItems.get(id);
      return item ? [{ ...item, content: null, pathname: null }] : [];
    });
  }

  async findLibraryItem(id: string) {
    return this.libraryItems.get(id);
  }

  async findLibraryItems(owner: string) {
    return [...this.libraryItems.values()].filter(
      (item) => item.ownerId === owner,
    );
  }

  async isLibraryDocumentAvailable(): Promise<boolean> {
    return true;
  }

  async restoreLibraryItems(rootIds: string[]) {
    for (const [id, item] of this.libraryItems) {
      if (item.deletionRootId && rootIds.includes(item.deletionRootId)) {
        this.libraryItems.set(id, {
          ...item,
          deletedAt: null,
          deletionRootId: null,
          purgeAfter: null,
        });
      }
    }
  }

  async trashLibraryItems(
    groups: Array<{ ids: string[]; rootId: string }>,
    deletedAt: Date,
    purgeAfter: Date,
  ) {
    for (const group of groups) {
      for (const id of group.ids) {
        const item = this.libraryItems.get(id);
        if (item) {
          this.libraryItems.set(id, {
            ...item,
            deletedAt,
            deletionRootId: group.rootId,
            purgeAfter,
          });
        }
      }
    }
  }

  async updateLibraryItem(
    id: string,
    input: { name?: string; parentId?: string | null },
  ): Promise<LibraryItemRecord> {
    const item = this.libraryItems.get(id);
    assert.ok(item);
    const updated = { ...item, ...input, updatedAt: new Date() };
    this.libraryItems.set(id, updated);
    return updated;
  }

  async deleteChat(id: string) {
    this.chats.delete(id);
  }

  async deleteProject(id: string): Promise<string[]> {
    this.projects.delete(id);
    for (const [chatId, chat] of this.chats) {
      if (chat.projectId === id) {
        this.chats.delete(chatId);
      }
    }
    return [];
  }

  async deleteProjectSource(sourceId: string): Promise<string> {
    this.sources.delete(sourceId);
    return 'source.txt';
  }

  async deleteDocumentsAfter() {}

  async deleteMessagesAfter() {}

  async deleteUserData() {}

  async findChat(id: string) {
    return this.chats.get(id);
  }

  async findChats(userId: string): Promise<ChatSummaryRow[]> {
    return [...this.chats.values()]
      .filter((chat) => chat.userId === userId)
      .map((chat) => ({ ...chat, projectName: null }));
  }

  async findDocument(): Promise<DocumentRow | undefined> {
    return undefined;
  }

  async findDocuments(): Promise<DocumentRow[]> {
    return [];
  }

  async findMessage(id: string) {
    return this.messages.get(id);
  }

  async findMessages(chatId: string) {
    return [...this.messages.values()].filter(
      (message) => message.chatId === chatId,
    );
  }

  async findObjectFiles(): Promise<ObjectFileRow[]> {
    return [];
  }

  async findProject(id: string): Promise<ProjectRow | undefined> {
    return this.projects.get(id);
  }

  async findProjectChats(project: string): Promise<ChatSummaryRow[]> {
    return [...this.chats.values()]
      .filter((chat) => chat.projectId === project)
      .map((chat) => ({
        ...chat,
        projectName: this.projects.get(project)?.name ?? null,
      }));
  }

  async findProjectContextMessages(): Promise<ProjectContextMessage[]> {
    return [];
  }

  async findProjectContextSources(): Promise<ProjectContextSource[]> {
    return [];
  }

  async findProjects(userId: string): Promise<ProjectSummary[]> {
    return [...this.projects.values()]
      .filter((project) => project.ownerId === userId)
      .map((project) => ({
        ...project,
        chatCount: [...this.chats.values()].filter(
          (chat) => chat.projectId === project.id,
        ).length,
        sourceCount: [...this.sources.values()].filter(
          (source) => source.projectId === project.id,
        ).length,
      }));
  }

  async findProjectSource(
    sourceId: string,
  ): Promise<ProjectSourceRow | undefined> {
    return this.sources.get(sourceId);
  }

  async findProjectSources(project: string): Promise<ProjectSourceSummary[]> {
    return [...this.sources.values()]
      .filter((source) => source.projectId === project)
      .map(({ extractedText: _, ...source }) => source);
  }

  async findSuggestions(): Promise<SuggestionRow[]> {
    return [];
  }

  async findVotes(): Promise<VoteRow[]> {
    return [];
  }

  async saveChat(
    id: string,
    userId: string,
    title: string,
    projectId?: string,
  ) {
    const chat = this.createChat(id, 'private', userId, title);
    chat.projectId = projectId ?? null;
    this.chats.set(id, chat);
    return chat;
  }

  async saveDocument(input: {
    content: string;
    id: string;
    kind: ArtifactKind;
    title: string;
    userId: string;
  }): Promise<DocumentRow> {
    return {
      content: input.content,
      createdAt: new Date(),
      id: input.id,
      text: input.kind,
      title: input.title,
      userId: input.userId,
    };
  }

  async saveMessages(input: SaveMessageInput[]) {
    for (const message of input) {
      this.messages.set(message.id, message);
    }
  }

  async saveObjectFile(input: {
    contentType: string;
    pathname: string;
    size: number;
    url: string;
    userId: string;
  }): Promise<ObjectFileRow> {
    return {
      ...input,
      createdAt: new Date(),
      id: '66666666-6666-4666-8666-666666666666',
    };
  }

  async saveProject(projectOwnerId: string, name: string): Promise<ProjectRow> {
    const project: ProjectRow = {
      createdAt: new Date(),
      id: '88888888-8888-4888-8888-888888888888',
      memoryMode: 'project_only',
      name,
      ownerId: projectOwnerId,
      updatedAt: new Date(),
    };
    this.projects.set(project.id, project);
    return project;
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
    const source: ProjectSourceRow = {
      contentType: input.contentType,
      createdAt: new Date(),
      extractedText: input.extractedText,
      id: '99999999-9999-4999-8999-999999999999',
      name: input.name,
      objectFileId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      projectId: input.projectId,
      size: input.size,
      updatedAt: new Date(),
    };
    this.sources.set(source.id, source);
    const { extractedText: _, ...summary } = source;
    return summary;
  }

  async saveSuggestions(_input: SaveSuggestionInput[]) {}

  async updateVisibility(id: string, visibility: ChatVisibility) {
    const chat = this.chats.get(id);
    assert.ok(chat);
    this.chats.set(id, { ...chat, visibility });
  }

  async updateProject(id: string, name: string): Promise<ProjectRow> {
    const project = this.projects.get(id);
    assert.ok(project);
    const updated = { ...project, name, updatedAt: new Date() };
    this.projects.set(id, updated);
    return updated;
  }

  async vote() {}

  private createChat(
    id: string,
    visibility: ChatVisibility,
    userId = ownerId,
    title = 'Chat',
  ): ChatRow {
    return {
      createdAt: new Date(),
      id,
      projectId: null,
      title,
      updatedAt: new Date(),
      userId,
      visibility,
    };
  }

  private createLibraryItem(
    input: Partial<LibraryItemRecord> &
      Pick<
        LibraryItemRecord,
        'id' | 'itemType' | 'name' | 'ownerId' | 'source'
      >,
  ): LibraryItemRecord {
    const now = new Date();
    return {
      contentType: null,
      createdAt: now,
      deletedAt: null,
      deletionRootId: null,
      documentId: null,
      objectFileId: null,
      parentId: null,
      purgeAfter: null,
      size: 0,
      updatedAt: now,
      url: null,
      ...input,
    };
  }
}

function createRpcRequest(
  signer: InternalRequestSigner,
  actorId: string,
  body: unknown,
) {
  const serializedBody = JSON.stringify(body);
  return new Request('https://conversation.example/api/rpc', {
    body: serializedBody,
    headers: signer.createHeaders({
      actorId,
      body: serializedBody,
      method: 'POST',
      target: '/api/rpc',
    }),
    method: 'POST',
  });
}

function createController(repository: ConversationRepositoryFake) {
  const signer = new InternalRequestSigner(secret);
  return {
    controller: new ConversationRpcController(
      new InternalRequestVerifier(signer),
      new ConversationService(repository),
    ),
    signer,
  };
}

test('private chats reject cross-user reads and writes', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const read = await controller.handle(
    createRpcRequest(signer, attackerId, {
      operation: 'getChat',
      payload: { id: privateChatId },
    }),
  );
  const write = await controller.handle(
    createRpcRequest(signer, attackerId, {
      operation: 'saveMessages',
      payload: {
        messages: [
          {
            attachments: [],
            chatId: privateChatId,
            createdAt: new Date().toISOString(),
            id: messageId,
            parts: [{ text: 'stolen', type: 'text' }],
            role: 'user',
          },
        ],
      },
    }),
  );

  assert.equal(read.status, 403);
  assert.equal(write.status, 403);
  assert.equal(repository.messages.size, 0);
});

test('public chats remain readable without write access', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const read = await controller.handle(
    createRpcRequest(signer, 'anonymous:visitor', {
      operation: 'getMessages',
      payload: { chatId: publicChatId },
    }),
  );

  assert.equal(read.status, 200);
});

test('chat owners can save messages', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const response = await controller.handle(
    createRpcRequest(signer, ownerId, {
      operation: 'saveMessages',
      payload: {
        messages: [
          {
            attachments: [],
            chatId: privateChatId,
            createdAt: new Date().toISOString(),
            id: messageId,
            parts: [{ text: 'hello', type: 'text' }],
            role: 'user',
          },
        ],
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(repository.messages.get(messageId)?.chatId, privateChatId);
});

test('projects reject cross-user reads', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const response = await controller.handle(
    createRpcRequest(signer, attackerId, {
      operation: 'getProject',
      payload: { id: projectId },
    }),
  );

  assert.equal(response.status, 403);
});

test('project chats are created private and cannot be published', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const chatId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const created = await controller.handle(
    createRpcRequest(signer, ownerId, {
      operation: 'saveChat',
      payload: { id: chatId, projectId, title: 'Project chat' },
    }),
  );
  const published = await controller.handle(
    createRpcRequest(signer, ownerId, {
      operation: 'updateVisibility',
      payload: { chatId, visibility: 'public' },
    }),
  );

  assert.equal(created.status, 200);
  assert.equal(repository.chats.get(chatId)?.projectId, projectId);
  assert.equal(repository.chats.get(chatId)?.visibility, 'private');
  assert.equal(published.status, 403);
  assert.equal(repository.chats.get(chatId)?.visibility, 'private');
});

test('saving a chat cannot cross project ownership', async () => {
  const repository = new ConversationRepositoryFake();
  const { controller, signer } = createController(repository);
  const chatId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const response = await controller.handle(
    createRpcRequest(signer, attackerId, {
      operation: 'saveChat',
      payload: { id: chatId, projectId, title: 'Stolen project chat' },
    }),
  );

  assert.equal(response.status, 403);
  assert.equal(repository.chats.has(chatId), false);
});
