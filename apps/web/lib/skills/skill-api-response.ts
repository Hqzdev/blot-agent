import {
  SkillForbiddenError,
  SkillNotFoundError,
  SkillValidationError,
} from '@teya/service-ai-gateway';

export function skillApiError(error: unknown): Response {
  if (error instanceof SkillValidationError) {
    return Response.json({ error: error.message }, { status: 400 });
  }
  if (error instanceof SkillNotFoundError) {
    return Response.json({ error: error.message }, { status: 404 });
  }
  if (error instanceof SkillForbiddenError) {
    return Response.json({ error: error.message }, { status: 403 });
  }
  console.error('Skill request failed', error);
  return Response.json(
    { error: 'Unable to complete request' },
    { status: 500 },
  );
}
