import { NextResponse } from 'next/server';

import { getBillingGateway } from '@/lib/services/billing-gateway';
import { billingOwner } from '@/lib/services/billing-identity';

export async function GET(request: Request) {
  const userId = await billingOwner(request);
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  return NextResponse.json({
    plan: await getBillingGateway().getSubscription(userId),
  });
}

export async function DELETE(request: Request) {
  const userId = await billingOwner(request);
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await getBillingGateway().cancelSubscription(userId);
  return NextResponse.json({ success: true });
}
