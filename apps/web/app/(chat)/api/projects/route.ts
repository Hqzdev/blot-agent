import { auth } from '@/app/(auth)/auth';
import { projectApiError } from '@/lib/projects/project-api-response';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { z } from 'zod';

const createProjectSchema = z.object({
  name: z.string().trim().min(1).max(80),
});

export async function GET(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const query = new URL(request.url).searchParams.get('query')?.trim();
  if (query && query.length > 80) {
    return Response.json({ error: 'Search is too long' }, { status: 400 });
  }
  try {
    const projects = await getConversationGateway().getProjects(userId, query);
    return Response.json(projects);
  } catch (error) {
    return projectApiError(error);
  }
}

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const parsed = createProjectSchema.safeParse(await request.json());
  if (!parsed.success) {
    return Response.json(
      { error: 'Project name must be between 1 and 80 characters' },
      { status: 400 },
    );
  }
  try {
    const project = await getConversationGateway().createProject(
      userId,
      parsed.data.name,
    );
    return Response.json(project, { status: 201 });
  } catch (error) {
    return projectApiError(error);
  }
}
