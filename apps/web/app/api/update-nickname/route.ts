import { updateNicknameSchema } from '@teya/contracts';
import { NextResponse } from 'next/server';
import { ZodError } from 'zod';

import { auth } from '@/app/(auth)/auth';
import { getIdentityGateway } from '@/lib/services/identity-gateway';

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const input = updateNicknameSchema.parse(await request.json());
    await getIdentityGateway().updateNickname(userId, input.nickname);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: 'Invalid nickname' }, { status: 400 });
    }
    if (error instanceof Error && error.message.includes('already')) {
      return NextResponse.json(
        { error: 'Nickname is already taken' },
        { status: 409 },
      );
    }
    return NextResponse.json(
      { error: 'Unable to update nickname' },
      { status: 500 },
    );
  }
}
