import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { LibraryDownloadBuilder } from '@/lib/library/library-download';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { z } from 'zod';

const requestSchema = z.object({
  ids: z.array(z.string().uuid()).min(1).max(20),
});

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const parsed = requestSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: 'Select between 1 and 20 Library items' },
        { status: 400 },
      );
    }
    const entries = await getConversationGateway().getLibraryDownloadManifest(
      userId,
      parsed.data.ids,
    );
    return new LibraryDownloadBuilder().zip(entries);
  } catch (error) {
    return libraryApiError(error);
  }
}
