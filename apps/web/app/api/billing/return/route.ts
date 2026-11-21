import { z } from 'zod';
import { billingOwner } from '@/lib/services/billing-identity';
import {
  redeemPaymentReturn,
  startPaymentReturn,
} from '@/lib/billing/payment-return';

const token = z.string().regex(/^[a-zA-Z0-9_-]{43}$/);
const input = z.discriminatedUnion('action', [
  z.object({
    action: z.literal('start'),
    challenge: token,
    invitation: token.optional(),
    platform: z.enum(['ios', 'macos']).default('ios'),
  }),
  z.object({
    action: z.literal('redeem'),
    id: z.string().uuid(),
    code: token,
    verifier: token,
  }),
]);
export async function POST(request: Request) {
  if (!request.headers.has('authorization'))
    return new Response(null, { status: 401 });
  const owner = await billingOwner(request);
  if (!owner) return new Response(null, { status: 401 });
  const parsed = input.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return new Response(null, { status: 400 });
  const data = parsed.data;
  const value =
    data.action === 'start'
      ? { id: await startPaymentReturn(owner, data.challenge, data.invitation, data.platform) }
      : await redeemPaymentReturn(owner, data.id, data.code, data.verifier);
  if (!value) return new Response(null, { status: 409 });
  return Response.json(value, {
    headers: { 'Cache-Control': 'private, no-store' },
  });
}
