import { updateProfileSchema } from '@teya/contracts';
import { NextResponse } from 'next/server';
import { ZodError } from 'zod';

import { auth } from '@/app/(auth)/auth';
import { getIdentityGateway } from '@/lib/services/identity-gateway';

export async function GET() {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const user = await getIdentityGateway().getUser(userId);
    return NextResponse.json(
      {
        customization: user.customization,
        email: user.email,
        hasPassword: Boolean(user.password),
        nickname: user.nickname,
        subscription: user.subscription,
      },
      {
        headers: {
          'cache-control': 'private, no-store',
        },
      },
    );
  } catch {
    return NextResponse.json(
      { error: 'Unable to load profile' },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const input = updateProfileSchema.parse(await request.json());
    await getIdentityGateway().updateCustomization(userId, input.customization);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: 'Invalid profile' }, { status: 400 });
    }
    return NextResponse.json(
      { error: 'Unable to update profile' },
      { status: 500 },
    );
  }
}
