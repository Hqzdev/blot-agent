import { NextResponse } from 'next/server';

import { auth } from '@/app/(auth)/auth';
import { LibraryUploadPolicy } from '@/lib/library/library-upload-policy';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let uploadedPathname: string | undefined;
  try {
    const formData = await request.formData();
    const file = formData.get('file');
    if (!(file instanceof File)) {
      return NextResponse.json({ error: 'File is required' }, { status: 400 });
    }
    new LibraryUploadPolicy().validate(file);
    const stored = await getObjectStorage().upload(userId, file);
    uploadedPathname = stored.pathname;
    const parent = formData.get('parentId');
    const item = await getConversationGateway().createLibraryUpload(userId, {
      ...stored,
      contentType: stored.contentType || 'application/octet-stream',
      name: file.name,
      parentId: typeof parent === 'string' && parent ? parent : null,
    });
    return NextResponse.json({
      ...stored,
      libraryItemId: item.id,
      name: item.name,
    });
  } catch (error) {
    if (uploadedPathname) {
      try {
        await getObjectStorage().delete([uploadedPathname]);
      } catch (cleanupError) {
        console.error('Library upload cleanup failed', cleanupError);
      }
    }
    return NextResponse.json(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Invalid file or upload failed',
      },
      { status: 400 },
    );
  }
}
