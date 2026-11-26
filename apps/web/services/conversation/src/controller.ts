import {
  type ConversationOperation,
  conversationOperationSchema,
} from '@teya/contracts';
import { InternalRequestVerifier } from '@teya/platform';
import { ZodError } from 'zod';

import {
  ConversationForbiddenError,
  ConversationNotFoundError,
  ConversationValidationError,
} from './errors';
import type { ConversationService } from './service';

export class ConversationRpcController {
  constructor(
    private readonly verifier: InternalRequestVerifier,
    private readonly service: ConversationService,
  ) {}

  async handle(request: Request): Promise<Response> {
    const body = await request.text();
    try {
      const identity = this.verifier.verify(request, body);
      const operation = conversationOperationSchema.parse(JSON.parse(body));
      const result = await this.execute(identity.actorId, operation);
      return Response.json({ result });
    } catch (error) {
      if (error instanceof SyntaxError || error instanceof ZodError) {
        return Response.json({ error: 'Invalid request' }, { status: 400 });
      }
      if (error instanceof ConversationValidationError) {
        return Response.json({ error: error.message }, { status: 400 });
      }
      if (error instanceof ConversationNotFoundError) {
        return Response.json({ error: error.message }, { status: 404 });
      }
      if (error instanceof ConversationForbiddenError) {
        return Response.json({ error: error.message }, { status: 403 });
      }
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }

  private execute(actorId: string, operation: ConversationOperation) {
    if (operation.operation === 'deleteUserData') {
      if (actorId !== 'system:web') {
        throw new ConversationForbiddenError(
          'Operation requires the web service',
        );
      }
      return this.service.deleteUserData(operation.payload.userId);
    }
    if (operation.operation === 'getExpiredLibraryItems') {
      if (actorId !== 'system:web') {
        throw new ConversationForbiddenError(
          'Operation requires the web service',
        );
      }
      return this.service.getExpiredLibraryItems(operation.payload.now);
    }
    if (operation.operation === 'purgeExpiredLibraryItems') {
      if (actorId !== 'system:web') {
        throw new ConversationForbiddenError(
          'Operation requires the web service',
        );
      }
      return this.service.purgeExpiredLibraryItems(operation.payload.ids);
    }

    if (actorId.startsWith('system:')) {
      throw new ConversationForbiddenError('Operation requires a user actor');
    }

    switch (operation.operation) {
      case 'getChats':
        return this.service.getChats(actorId);
      case 'getChat':
        return this.service.getChat(actorId, operation.payload.id);
      case 'saveChat':
        return this.service.saveChat(
          actorId,
          operation.payload.id,
          operation.payload.title,
          operation.payload.projectId,
        );
      case 'getProjects':
        return this.service.getProjects(actorId, operation.payload.query);
      case 'getProject':
        return this.service.getProject(actorId, operation.payload.id);
      case 'createProject':
        return this.service.createProject(actorId, operation.payload.name);
      case 'updateProject':
        return this.service.updateProject(
          actorId,
          operation.payload.id,
          operation.payload.name,
        );
      case 'deleteProject':
        return this.service.deleteProject(actorId, operation.payload.id);
      case 'getProjectChats':
        return this.service.getProjectChats(
          actorId,
          operation.payload.projectId,
        );
      case 'getProjectSources':
        return this.service.getProjectSources(
          actorId,
          operation.payload.projectId,
        );
      case 'saveProjectSource':
        return this.service.saveProjectSource(actorId, operation.payload);
      case 'deleteProjectSource':
        return this.service.deleteProjectSource(
          actorId,
          operation.payload.projectId,
          operation.payload.sourceId,
        );
      case 'getProjectContext':
        return this.service.getProjectContext(
          actorId,
          operation.payload.projectId,
          operation.payload.currentChatId,
        );
      case 'deleteChat':
        return this.service.deleteChat(actorId, operation.payload.id);
      case 'getMessages':
        return this.service.getMessages(actorId, operation.payload.chatId);
      case 'saveMessages':
        return this.service.saveMessages(actorId, operation.payload.messages);
      case 'getVotes':
        return this.service.getVotes(actorId, operation.payload.chatId);
      case 'vote':
        return this.service.vote(
          actorId,
          operation.payload.chatId,
          operation.payload.messageId,
          operation.payload.type,
        );
      case 'getDocument':
        return this.service.getDocument(actorId, operation.payload.id);
      case 'getDocuments':
        return this.service.getDocuments(actorId, operation.payload.id);
      case 'saveDocument':
        return this.service.saveDocument(actorId, operation.payload);
      case 'deleteDocumentsAfter':
        return this.service.deleteDocumentsAfter(
          actorId,
          operation.payload.id,
          operation.payload.timestamp,
        );
      case 'getSuggestions':
        return this.service.getSuggestions(
          actorId,
          operation.payload.documentId,
        );
      case 'saveSuggestions':
        return this.service.saveSuggestions(
          actorId,
          operation.payload.suggestions,
        );
      case 'getMessage':
        return this.service.getMessage(actorId, operation.payload.id);
      case 'deleteMessagesAfter':
        return this.service.deleteMessagesAfter(
          actorId,
          operation.payload.chatId,
          operation.payload.timestamp,
        );
      case 'updateVisibility':
        return this.service.updateVisibility(
          actorId,
          operation.payload.chatId,
          operation.payload.visibility,
        );
      case 'getObjectFiles':
        return this.service.getObjectFiles(actorId);
      case 'saveObjectFile':
        return this.service.saveObjectFile(actorId, operation.payload);
      case 'listLibraryItems':
        return this.service.listLibraryItems(actorId, operation.payload);
      case 'getLibraryItem':
        return this.service.getLibraryItem(actorId, operation.payload.id);
      case 'createLibraryFolder':
        return this.service.createLibraryFolder(actorId, operation.payload);
      case 'createLibraryUpload':
        return this.service.createLibraryUpload(actorId, operation.payload);
      case 'updateLibraryItem':
        return this.service.updateLibraryItem(
          actorId,
          operation.payload.id,
          operation.payload,
        );
      case 'trashLibraryItems':
        return this.service.trashLibraryItems(actorId, operation.payload.ids);
      case 'restoreLibraryItems':
        return this.service.restoreLibraryItems(actorId, operation.payload.ids);
      case 'permanentlyDeleteLibraryItems':
        return this.service.permanentlyDeleteLibraryItems(
          actorId,
          operation.payload.ids,
        );
      case 'bulkLibraryItems':
        return this.service.bulkLibraryItems(actorId, operation.payload);
      case 'getLibraryDownloadManifest':
        return this.service.getLibraryDownloadManifest(
          actorId,
          operation.payload.ids,
        );
    }
  }
}
