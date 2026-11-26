import type { ChatSummaryRow, ProjectRow } from '@teya/database';
import type {
  ProjectSourceSummary,
  ProjectSummary,
} from '@teya/service-conversation';

export type Project = ProjectRow;
export type ProjectListItem = ProjectSummary;
export type ProjectSource = ProjectSourceSummary;
export type ProjectChat = ChatSummaryRow;

export interface ProjectDetails {
  chats: ProjectChat[];
  project: Project;
  sources: ProjectSource[];
}
