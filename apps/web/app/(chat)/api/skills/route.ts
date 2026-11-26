import { auth } from '@/app/(auth)/auth';
import { getSkillGateway } from '@/lib/services/skill-gateway';
import { skillApiError } from '@/lib/skills/skill-api-response';
import { skillInputSchema } from '@teya/contracts';

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
    return Response.json(await getSkillGateway().listSkills(userId, query));
  } catch (error) {
    return skillApiError(error);
  }
}

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const parsed = skillInputSchema.safeParse(await request.json());
    if (!parsed.success) {
      return Response.json(
        { error: 'Complete every field within its character limit' },
        { status: 400 },
      );
    }
    const skill = await getSkillGateway().createSkill(userId, parsed.data);
    return Response.json(skill, { status: 201 });
  } catch (error) {
    return skillApiError(error);
  }
}
