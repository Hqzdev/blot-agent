import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { libraryListInputSchema } from '@teya/contracts';

export async function GET(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const params = new URL(request.url).searchParams;
  const parsed = libraryListInputSchema.safeParse({
    category: params.get('category') ?? undefined,
    cursor: params.get('cursor') ?? undefined,
    deleted: params.get('deleted') === 'true',
    direction: params.get('direction') ?? undefined,
    limit: params.has('limit') ? Number(params.get('limit')) : undefined,
    parentId: params.has('parentId')
      ? params.get('parentId') || null
      : undefined,
    query: params.get('query') ?? undefined,
    sort: params.get('sort') ?? undefined,
    source: params.get('source') ?? undefined,
    tab: params.get('tab') ?? undefined,
  });
  if (!parsed.success) {
    return Response.json({ error: 'Invalid Library filters' }, { status: 400 });
  }
  try {
    return Response.json(
      await getConversationGateway().listLibraryItems(userId, parsed.data),
    );
  } catch (error) {
    return libraryApiError(error);
  }
}
