import { auth } from '@/app/(auth)/auth';
import { projectApiError } from '@/lib/projects/project-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';
import { z } from 'zod';

const identifierSchema = z.string().uuid();

export async function DELETE(
  _request: Request,
  context: { params: Promise<{ id: string; sourceId: string }> },
) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const { id, sourceId } = await context.params;
  if (
    !identifierSchema.safeParse(id).success ||
    !identifierSchema.safeParse(sourceId).success
  ) {
    return Response.json({ error: 'Source not found' }, { status: 404 });
  }
  try {
    const pathname = await getConversationGateway().deleteProjectSource(
      userId,
      id,
      sourceId,
    );
    try {
      await getObjectStorage().delete([pathname]);
    } catch (error) {
      console.error('Project source Blob cleanup failed', error);
    }
    return new Response(null, { status: 204 });
  } catch (error) {
    return projectApiError(error);
  }
}
