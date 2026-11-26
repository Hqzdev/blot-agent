import { billingPath } from '@/lib/billing/path';
import { createCheckoutSchema } from '@teya/contracts';
import { bindPayment, validAttempt } from '@/lib/billing/payment-return';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { z, ZodError } from 'zod';

import { auth } from '@/app/(auth)/auth';
import { getBillingGateway } from '@/lib/services/billing-gateway';
import { getIdentityGateway } from '@/lib/services/identity-gateway';

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const input = createCheckoutSchema
      .omit({ returnUrl: true })
      .extend({ attemptId: z.string().uuid().optional() })
      .parse(await request.json());
    if (input.attemptId && !(await validAttempt(userId, input.attemptId)))
      return NextResponse.json(
        { error: 'Откройте оплату из того же аккаунта Ori.' },
        { status: 403 },
      );
    const origin = new URL(process.env.AUTH_URL || request.url).origin;
    const returnUrl = new URL(
      billingPath('/payment/success'),
      origin,
    ).toString();
    const user = await getIdentityGateway().getUser(userId);
    const checkout = await getBillingGateway().createCheckout({
      cardId: input.cardId,
      customerEmail: user.email,
      idempotencyKey: input.idempotencyKey,
      plan: input.plan,
      returnUrl,
      userId,
    });
    if (
      input.attemptId &&
      !(await bindPayment(userId, input.attemptId, checkout.paymentId))
    )
      return NextResponse.json(
        { error: 'Начните новую оплату из Ori.' },
        { status: 409 },
      );
    const cookieStore = await cookies();
    cookieStore.set('teya-payment-id', checkout.paymentId, {
      httpOnly: true,
      maxAge: 60 * 60,
      path: '/',
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
    });
    return NextResponse.json(checkout);
  } catch (error) {
    if (error instanceof ZodError || error instanceof SyntaxError) {
      return NextResponse.json(
        { error: 'Invalid checkout request' },
        { status: 400 },
      );
    }
    return NextResponse.json(
      { error: 'Unable to create payment' },
      { status: 502 },
    );
  }
}
