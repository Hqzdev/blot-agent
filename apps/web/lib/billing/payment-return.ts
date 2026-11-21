import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { DatabaseConnectionProvider } from '@teya/database/connection';
const sql = () => new DatabaseConnectionProvider().get().client;
const digest = (s: string) =>
  createHash('sha256').update(s).digest('base64url');

function newReturnCode(owner: string, payment: string) {
  const secret = process.env.AUTH_SECRET;
  if (!secret) throw new Error('Account signing secret is unavailable');
  const privateAccountId = createHmac('sha256', secret)
    .update('blot/billing/account/v1\0')
    .update(owner.toLowerCase())
    .digest();
  return createHmac('sha256', privateAccountId)
    .update('blot/billing/return/v1\0')
    .update(payment.toLowerCase())
    .update(randomBytes(32))
    .digest('base64url');
}
export async function startPaymentReturn(
  owner: string,
  challenge: string,
  invitation?: string,
  platform: 'ios' | 'macos' = 'ios',
) {
  if (
    invitation &&
    digest(invitation) === process.env.BLOT_TEST_INVITATION_DIGEST
  ) {
    await sql()`INSERT INTO billing.quota_pilots(invitation_digest,user_id) VALUES (${digest(invitation)},${owner}) ON CONFLICT DO NOTHING`;
  }
  const id = randomUUID();
  await sql()`INSERT INTO billing.payment_returns(id,user_id,device_challenge,platform,expires_at)
    VALUES (${id},${owner},${challenge},${platform},now()+interval '1 hour')`;
  return id;
}
export async function validAttempt(owner: string, id: string) {
  const [row] =
    await sql()`SELECT id FROM billing.payment_returns WHERE id=${id} AND user_id=${owner} AND expires_at>now()`;
  return !!row;
}
export async function bindPayment(owner: string, id: string, payment: string) {
  const rows =
    await sql()`UPDATE billing.payment_returns SET payment_id=${payment}
    WHERE id=${id} AND user_id=${owner} AND expires_at>now()
      AND (payment_id IS NULL OR payment_id=${payment}) RETURNING id`;
  return rows.length === 1;
}
export async function issuePaymentReturn(owner: string, payment: string) {
  const code = newReturnCode(owner, payment);
  const [row] =
    await sql()`UPDATE billing.payment_returns r SET code_hash=${digest(code)},code_expires_at=now()+interval '5 minutes'
    FROM billing.payments p WHERE r.payment_id=p.id AND p.id=${payment} AND p.user_id=${owner} AND r.user_id=p.user_id
      AND p.test AND p.status='succeeded' AND r.expires_at>now() RETURNING r.id,r.platform`;
  return row ? { id: row.id, code, platform: row.platform } : null;
}
export async function redeemPaymentReturn(
  owner: string,
  id: string,
  code: string,
  verifier: string,
) {
  const [row] =
    await sql()`DELETE FROM billing.payment_returns r USING billing.payments p
    WHERE r.payment_id=p.id AND r.id=${id} AND r.user_id=${owner} AND p.user_id=r.user_id AND p.test
      AND p.status='succeeded' AND r.code_hash=${digest(code)} AND r.device_challenge=${digest(verifier)}
      AND r.code_expires_at>now() AND r.expires_at>now() RETURNING p.plan,p.test,p.card_id AS "cardID"`;
  return row;
}
