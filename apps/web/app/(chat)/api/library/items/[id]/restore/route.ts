import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { z } from 'zod';

const idSchema = z.string().uuid();

export async function POST(
  _request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const { id } = await context.params;
  if (!idSchema.safeParse(id).success) {
    return Response.json({ error: 'Library item not found' }, { status: 404 });
  }
  try {
    await getConversationGateway().restoreLibraryItems(userId, [id]);
    return new Response(null, { status: 204 });
  } catch (error) {
    return libraryApiError(error);
  }
}
