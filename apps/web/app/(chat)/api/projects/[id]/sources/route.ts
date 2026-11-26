import { auth } from '@/app/(auth)/auth';
import { projectApiError } from '@/lib/projects/project-api-response';
import { ProjectSourceExtractor } from '@/lib/projects/project-source-extractor';
import { getConversationGateway } from '@/lib/services/conversation-gateway';
import { getObjectStorage } from '@/lib/services/object-storage';
import { z } from 'zod';

const projectIdSchema = z.string().uuid();

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
    const sources = await getConversationGateway().getProjectSources(
      userId,
      id,
    );
    return Response.json(sources);
  } catch (error) {
    return projectApiError(error);
  }
}

export async function POST(
  request: Request,
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
  let uploadedPathname: string | undefined;
  try {
    const gateway = getConversationGateway();
    await gateway.getProject(userId, id);
    const formData = await request.formData();
    const file = formData.get('file');
    if (!(file instanceof File)) {
      return Response.json({ error: 'File is required' }, { status: 400 });
    }
    const extracted = await new ProjectSourceExtractor().extract(file);
    const stored = await getObjectStorage().upload(userId, extracted.file);
    uploadedPathname = stored.pathname;
    const source = await gateway.saveProjectSource(userId, {
      contentType: extracted.contentType,
      extractedText: extracted.text,
      name: extracted.name,
      pathname: stored.pathname,
      projectId: id,
      size: extracted.size,
      url: stored.url,
    });
    return Response.json(source, { status: 201 });
  } catch (error) {
    if (uploadedPathname) {
      try {
        await getObjectStorage().delete([uploadedPathname]);
      } catch (cleanupError) {
        console.error('Project source Blob cleanup failed', cleanupError);
      }
    }
    return projectApiError(error);
  }
}
