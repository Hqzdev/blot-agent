import 'server-only';

import type { ArtifactKind } from '@/components/artifact';
import {
  type ConversationGateway,
  getConversationGateway,
} from '@/lib/services/conversation-gateway';
import { getIdentityGateway } from '@/lib/services/identity-gateway';
import type { Customization } from '@teya/contracts';

import type { Chat, DBMessage, Document, Suggestion, Vote } from './schema';

function conversation(): ConversationGateway {
  return getConversationGateway();
}

export function saveChat({
  id,
  userId,
  title,
  projectId,
}: {
  id: string;
  userId: string;
  title: string;
  projectId?: string;
}): Promise<Chat> {
  return conversation().saveChat(userId, id, title, projectId);
}

export function deleteChatById({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<void> {
  return conversation().deleteChat(userId, id);
}

export function getChatsByUserId({ id }: { id: string }): Promise<Chat[]> {
  return conversation().getChats(id);
}

export function getChatById({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<Chat | null> {
  return conversation().getChat(userId, id);
}

export function saveMessages({
  messages,
  userId,
}: {
  messages: DBMessage[];
  userId: string;
}): Promise<void> {
  return conversation().saveMessages(userId, messages);
}

export function getMessagesByChatId({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<DBMessage[]> {
  return conversation().getMessages(userId, id);
}

export function voteMessage({
  chatId,
  messageId,
  type,
  userId,
}: {
  chatId: string;
  messageId: string;
  type: 'up' | 'down';
  userId: string;
}): Promise<void> {
  return conversation().vote(userId, chatId, messageId, type);
}

export function getVotesByChatId({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<Vote[]> {
  return conversation().getVotes(userId, id);
}

export function saveDocument({
  id,
  title,
  kind,
  content,
  userId,
}: {
  id: string;
  title: string;
  kind: ArtifactKind;
  content: string;
  userId: string;
}): Promise<Document> {
  return conversation().saveDocument(userId, {
    content,
    id,
    kind,
    title,
  });
}

export function getDocumentsById({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<Document[]> {
  return conversation().getDocuments(userId, id);
}

export function getDocumentById({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<Document> {
  return conversation().getDocument(userId, id);
}

export function deleteDocumentsByIdAfterTimestamp({
  id,
  timestamp,
  userId,
}: {
  id: string;
  timestamp: Date;
  userId: string;
}): Promise<void> {
  return conversation().deleteDocumentsAfter(userId, id, timestamp);
}

export function saveSuggestions({
  suggestions,
  userId,
}: {
  suggestions: Array<Omit<Suggestion, 'userId'>>;
  userId: string;
}): Promise<void> {
  return conversation().saveSuggestions(userId, suggestions);
}

export function getSuggestionsByDocumentId({
  documentId,
  userId,
}: {
  documentId: string;
  userId: string;
}): Promise<Suggestion[]> {
  return conversation().getSuggestions(userId, documentId);
}

export async function getMessageById({
  id,
  userId,
}: {
  id: string;
  userId: string;
}): Promise<DBMessage[]> {
  return [await conversation().getMessage(userId, id)];
}

export function deleteMessagesByChatIdAfterTimestamp({
  chatId,
  timestamp,
  userId,
}: {
  chatId: string;
  timestamp: Date;
  userId: string;
}): Promise<void> {
  return conversation().deleteMessagesAfter(userId, chatId, timestamp);
}

export function updateChatVisiblityById({
  chatId,
  visibility,
  userId,
}: {
  chatId: string;
  visibility: 'private' | 'public';
  userId: string;
}): Promise<void> {
  return conversation().updateVisibility(userId, chatId, visibility);
}

export async function getUserCustomization(userId: string): Promise<unknown> {
  return (await getIdentityGateway().getUser(userId)).customization;
}

export function updateUserCustomization({
  userId,
  customization,
}: {
  userId: string;
  customization: Customization;
}) {
  return getIdentityGateway().updateCustomization(userId, customization);
}
