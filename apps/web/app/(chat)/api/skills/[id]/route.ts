import { auth } from '@/app/(auth)/auth';
import { getSkillGateway } from '@/lib/services/skill-gateway';
import { skillApiError } from '@/lib/skills/skill-api-response';
import { skillInputSchema } from '@teya/contracts';
import { z } from 'zod';

const skillIdSchema = z.string().uuid();

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
  if (!skillIdSchema.safeParse(id).success) {
    return Response.json({ error: 'Skill not found' }, { status: 404 });
  }
  try {
    return Response.json(await getSkillGateway().getSkill(userId, id));
  } catch (error) {
    return skillApiError(error);
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
  try {
    const parsedId = skillIdSchema.safeParse(id);
    const parsedInput = skillInputSchema.safeParse(await request.json());
    if (!parsedId.success || !parsedInput.success) {
      return Response.json({ error: 'Invalid skill update' }, { status: 400 });
    }
    return Response.json(
      await getSkillGateway().updateSkill(userId, id, parsedInput.data),
    );
  } catch (error) {
    return skillApiError(error);
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
  if (!skillIdSchema.safeParse(id).success) {
    return Response.json({ error: 'Skill not found' }, { status: 404 });
  }
  try {
    await getSkillGateway().deleteSkill(userId, id);
    return new Response(null, { status: 204 });
  } catch (error) {
    return skillApiError(error);
  }
}
