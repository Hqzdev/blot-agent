import {
  ConversationForbiddenError,
  ConversationNotFoundError,
  ConversationValidationError,
} from '@teya/service-conversation';
import { ProjectSourceValidationError } from './project-source-extractor';

export function projectApiError(error: unknown): Response {
  if (
    error instanceof ConversationValidationError ||
    error instanceof ProjectSourceValidationError
  ) {
    return Response.json({ error: error.message }, { status: 400 });
  }
  if (error instanceof ConversationNotFoundError) {
    return Response.json({ error: error.message }, { status: 404 });
  }
  if (error instanceof ConversationForbiddenError) {
    return Response.json({ error: error.message }, { status: 403 });
  }
  console.error('Project request failed', error);
  return Response.json(
    { error: 'Unable to complete request' },
    { status: 500 },
  );
}
