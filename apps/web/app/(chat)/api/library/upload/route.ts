import { auth } from '@/app/(auth)/auth';
import { LibraryUploadPolicy } from '@/lib/library/library-upload-policy';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';
import { type HandleUploadBody, handleUpload } from '@vercel/blob/client';
import { z } from 'zod';

const payloadSchema = z.object({
  contentType: z.string().max(255),
  name: z.string().trim().min(1).max(255),
  parentId: z.string().uuid().nullable(),
  size: z
    .number()
    .int()
    .positive()
    .max(25 * 1024 * 1024),
});

const tokenPayloadSchema = payloadSchema.extend({
  userId: z.string().uuid(),
});

export async function POST(request: Request) {
  if (!process.env.BLOB_READ_WRITE_TOKEN) {
    return Response.json(
      { error: 'Direct upload is unavailable' },
      { status: 503 },
    );
  }
  const body = (await request.json()) as HandleUploadBody;
  try {
    const result = await handleUpload({
      body,
      onBeforeGenerateToken: async (_pathname, clientPayload) => {
        const session = await auth();
        const userId = session?.user?.id;
        if (!userId) {
          throw new Error('Unauthorized');
        }
        const payload = payloadSchema.parse(JSON.parse(clientPayload ?? ''));
        new LibraryUploadPolicy().validateMetadata(payload.name, payload.size);
        if (payload.parentId) {
          await getConversationGateway().getLibraryItem(
            userId,
            payload.parentId,
          );
        }
        return {
          addRandomSuffix: false,
          allowedContentTypes: payload.contentType
            ? [payload.contentType]
            : undefined,
          maximumSizeInBytes: 25 * 1024 * 1024,
          tokenPayload: JSON.stringify({ ...payload, userId }),
        };
      },
      onUploadCompleted: async ({ blob, tokenPayload }) => {
        const payload = tokenPayloadSchema.parse(
          JSON.parse(tokenPayload ?? ''),
        );
        try {
          await getConversationGateway().createLibraryUpload(payload.userId, {
            contentType:
              blob.contentType ||
              payload.contentType ||
              'application/octet-stream',
            name: payload.name,
            parentId: payload.parentId,
            pathname: blob.pathname,
            size: payload.size,
            url: blob.url,
          });
        } catch (error) {
          await getObjectStorage().delete([blob.pathname]);
          throw error;
        }
      },
      request,
    });
    return Response.json(result);
  } catch (error) {
    console.error('Library client upload failed', error);
    return Response.json({ error: 'Upload failed' }, { status: 400 });
  }
}
