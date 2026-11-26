import { auth } from '@/app/(auth)/auth';
import { BlotAccountClient } from '@/lib/auth/blot-account-client';
import { getBillingGateway } from '@/lib/services/billing-gateway';
import { NextResponse } from 'next/server';
import { z } from 'zod';

export async function GET(request: Request) {
  try {
    const header = request.headers.get('authorization');
    const userId = header
      ? (
          await new BlotAccountClient().profile(
            z
              .string()
              .regex(/^Bearer [A-Za-z0-9_-]{43}$/)
              .parse(header)
              .slice(7),
          )
        ).id
      : (await auth())?.user?.id;
    if (!userId)
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    const cardId = z
      .string()
      .uuid()
      .parse(new URL(request.url).searchParams.get('cardId'));
    return NextResponse.json(
      await getBillingGateway().getCardPaymentStatus(userId, cardId),
      { headers: { 'cache-control': 'private, no-store' } },
    );
  } catch {
    return NextResponse.json({ error: 'Payment not found' }, { status: 404 });
  }
}
