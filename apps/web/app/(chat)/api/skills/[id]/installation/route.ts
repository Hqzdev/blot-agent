import { auth } from '@/app/(auth)/auth';
import { getSkillGateway } from '@/lib/services/skill-gateway';
import { skillApiError } from '@/lib/skills/skill-api-response';
import { z } from 'zod';

const skillIdSchema = z.string().uuid();

export async function PUT(
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
    return Response.json(await getSkillGateway().installSkill(userId, id));
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
    return Response.json(await getSkillGateway().uninstallSkill(userId, id));
  } catch (error) {
    return skillApiError(error);
  }
}
