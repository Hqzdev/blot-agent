import { auth } from '@/app/(auth)/auth';
import { projectApiError } from '@/lib/projects/project-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';
import { z } from 'zod';

const projectIdSchema = z.string().uuid();
const updateProjectSchema = z.object({
  name: z.string().trim().min(1).max(80),
});

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
  if (!projectIdSchema.safeParse(id).success) {
    return Response.json({ error: 'Project not found' }, { status: 404 });
  }
  try {
    const gateway = getConversationGateway();
    const [project, chats, sources] = await Promise.all([
      gateway.getProject(userId, id),
      gateway.getProjectChats(userId, id),
      gateway.getProjectSources(userId, id),
    ]);
    return Response.json({ chats, project, sources });
  } catch (error) {
    return projectApiError(error);
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
  const parsedId = projectIdSchema.safeParse(id);
  const parsedBody = updateProjectSchema.safeParse(await request.json());
  if (!parsedId.success || !parsedBody.success) {
    return Response.json({ error: 'Invalid project update' }, { status: 400 });
  }
  try {
    const project = await getConversationGateway().updateProject(
      userId,
      id,
      parsedBody.data.name,
    );
    return Response.json(project);
  } catch (error) {
    return projectApiError(error);
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
  if (!projectIdSchema.safeParse(id).success) {
    return Response.json({ error: 'Project not found' }, { status: 404 });
  }
  try {
    const pathnames = await getConversationGateway().deleteProject(userId, id);
    try {
      await getObjectStorage().delete(pathnames);
    } catch (error) {
      console.error('Project Blob cleanup failed', error);
    }
    return new Response(null, { status: 204 });
  } catch (error) {
    return projectApiError(error);
  }
}
