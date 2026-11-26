import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    return Response.json({ error: 'Cron is not configured' }, { status: 503 });
  }
  if (request.headers.get('authorization') !== `Bearer ${secret}`) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const gateway = getConversationGateway();
  const ids = await gateway.getExpiredLibraryItems(new Date());
  const pathnames = await gateway.purgeExpiredLibraryItems(ids);
  try {
    await getObjectStorage().delete(pathnames);
  } catch (error) {
    console.error('Expired Library Blob cleanup failed', error);
    return Response.json(
      { error: 'Database purge completed but Blob cleanup failed' },
      { status: 502 },
    );
  }
  return Response.json({
    blobsDeleted: pathnames.length,
    itemsPurged: ids.length,
  });
}
