import type { Plan } from '@teya/contracts';
import {
  type ChatRow,
  type ChatSummaryRow,
  type DocumentRow,
  type MessageRow,
  type SuggestionRow,
  type UserRow,
  type VoteRow,
  chats,
  documents,
  messages,
  suggestions,
  users,
  votes,
} from '@teya/database';

export {
  chats as chat,
  documents as document,
  messages as message,
  suggestions as suggestion,
  users as user,
  votes as vote,
};

export type User = UserRow & { subscription: Plan };
export type Chat = ChatRow;
export type ChatSummary = ChatSummaryRow;
export type DBMessage = MessageRow;
export type Vote = VoteRow;
export type Document = DocumentRow;
export type Suggestion = SuggestionRow;
