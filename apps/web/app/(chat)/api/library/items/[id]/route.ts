import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { libraryUpdateItemSchema } from '@teya/contracts';
import { z } from 'zod';

const idSchema = z.string().uuid();

export async function GET(
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
    return Response.json(
      await getConversationGateway().getLibraryItem(userId, id),
    );
  } catch (error) {
    return libraryApiError(error);
  }
}

export async function PATCH(
  request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const { id } = await context.params;
  const parsed = libraryUpdateItemSchema.safeParse(await request.json());
  if (!idSchema.safeParse(id).success || !parsed.success) {
    return Response.json({ error: 'Invalid Library update' }, { status: 400 });
  }
  try {
    return Response.json(
      await getConversationGateway().updateLibraryItem(userId, id, parsed.data),
    );
  } catch (error) {
    return libraryApiError(error);
  }
}

export async function DELETE(
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
    await getConversationGateway().trashLibraryItems(userId, [id]);
    return new Response(null, { status: 204 });
  } catch (error) {
    return libraryApiError(error);
  }
}
