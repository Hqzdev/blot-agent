import { usageOverview } from '@/lib/billing/usage';
import { getBillingGateway } from '@/lib/services/billing-gateway';
import { billingOwner } from '@/lib/services/billing-identity';
import { NextResponse } from 'next/server';

export async function GET(request: Request) {
  try {
    const userId = await billingOwner(request);
    if (!userId)
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    const gateway = getBillingGateway();
    const [plan, payments, usage] = await Promise.all([
      gateway.getSubscription(userId),
      new URL(request.url).searchParams.get('view') === 'subscription'
        ? []
        : gateway.getPaymentHistory(userId),
      usageOverview(userId),
    ]);
    return NextResponse.json(
      { plan, payments, usage },
      { headers: { 'cache-control': 'private, no-store' } },
    );
  } catch {
    return NextResponse.json({ error: 'Billing unavailable' }, { status: 502 });
  }
}
