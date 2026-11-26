import {
  ConversationForbiddenError,
  ConversationNotFoundError,
  ConversationValidationError,
} from '@teya/service-conversation';
import { ZodError } from 'zod';

export function libraryApiError(error: unknown): Response {
  if (
    error instanceof ConversationValidationError ||
    error instanceof ZodError
  ) {
    return Response.json({ error: error.message }, { status: 400 });
  }
  if (error instanceof ConversationNotFoundError) {
    return Response.json({ error: error.message }, { status: 404 });
  }
  if (error instanceof ConversationForbiddenError) {
    return Response.json({ error: error.message }, { status: 403 });
  }
  console.error('Library request failed', error);
  return Response.json(
    { error: 'Unable to complete the Library request' },
    { status: 500 },
  );
}
