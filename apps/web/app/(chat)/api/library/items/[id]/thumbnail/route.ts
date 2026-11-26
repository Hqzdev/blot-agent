import { auth } from '@/app/(auth)/auth';
import { libraryApiError } from '@/lib/library/library-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
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
    const [entry] = await getConversationGateway().getLibraryDownloadManifest(
      userId,
      [id],
    );
    if (!entry?.contentType.startsWith('image/')) {
      return Response.json({ error: 'Thumbnail not found' }, { status: 404 });
    }
    if (entry.content !== null) {
      return new Response(
        Uint8Array.from(Buffer.from(entry.content, 'base64')),
        {
          headers: {
            'Cache-Control': 'private, max-age=300',
            'Content-Type': entry.contentType,
          },
        },
      );
    }
    if (entry.url) {
      return Response.redirect(entry.url);
    }
    return Response.json({ error: 'Thumbnail not found' }, { status: 404 });
  } catch (error) {
    return libraryApiError(error);
  }
}
