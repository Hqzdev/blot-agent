import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { libraryCreateFolderSchema } from '@teya/contracts';

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const parsed = libraryCreateFolderSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: 'Folder name must be between 1 and 255 characters' },
        { status: 400 },
      );
    }
    const item = await getConversationGateway().createLibraryFolder(
      userId,
      parsed.data,
    );
    return Response.json(item, { status: 201 });
  } catch (error) {
    return libraryApiError(error);
  }
}
