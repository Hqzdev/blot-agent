import { auth } from '@/app/(auth)/auth';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { ConversationForbiddenError } from '@teya/service-conversation';

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await auth();
  if (!session?.user?.id)
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id))
    return Response.json({ error: 'Invalid conversation' }, { status: 400 });
  try {
    const gateway = getConversationGateway();
    const chat = await gateway.getChat(session.user.id, id);
    return Response.json(
      chat ? await gateway.getMessages(session.user.id, id) : [],
      { headers: { 'Cache-Control': 'private, no-store' } },
    );
  } catch (error) {
    if (error instanceof ConversationForbiddenError)
      return Response.json({ error: 'Forbidden' }, { status: 403 });
    return Response.json(
      { error: 'History synchronization unavailable' },
      { status: 503 },
    );
  }
}
