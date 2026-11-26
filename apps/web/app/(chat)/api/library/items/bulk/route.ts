import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';
import { libraryBulkInputSchema } from '@teya/contracts';

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const parsed = libraryBulkInputSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: 'Select between 1 and 20 Library items' },
        { status: 400 },
      );
    }
    const pathnames = await getConversationGateway().bulkLibraryItems(
      userId,
      parsed.data,
    );
    if (parsed.data.action === 'permanent') {
      await getObjectStorage().delete(pathnames);
    }
    return new Response(null, { status: 204 });
  } catch (error) {
    return libraryApiError(error);
  }
}
