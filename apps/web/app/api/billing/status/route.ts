import { issuePaymentReturn } from '@/lib/billing/payment-return';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { auth } from '@/app/(auth)/auth';
import { getBillingGateway } from '@/lib/services/billing-gateway';

export async function GET() {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const cookieStore = await cookies();
  const paymentId = cookieStore.get('teya-payment-id')?.value;
  if (!paymentId) {
    return NextResponse.json({ error: 'Payment not found' }, { status: 404 });
  }

  try {
    const payment = await getBillingGateway().getPaymentStatus(
      userId,
      paymentId,
    );
    const handoff =
      payment.test && payment.status === 'succeeded'
        ? await issuePaymentReturn(userId, paymentId)
        : null;
    return NextResponse.json(
      { ...payment, handoff },
      {
        headers: {
          'cache-control': 'private, no-store',
        },
      },
    );
  } catch {
    return NextResponse.json({ error: 'Payment not found' }, { status: 404 });
  }
}
