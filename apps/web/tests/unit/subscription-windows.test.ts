import assert from 'node:assert/strict';
import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { DatabaseConnectionProvider } from '@teya/database/connection';
import {
  reserveUsage,
  settleUsage,
  usageOverview,
  QuotaExceeded,
} from '../../lib/billing/usage';
import {
  bindPayment,
  issuePaymentReturn,
  redeemPaymentReturn,
  startPaymentReturn,
} from '../../lib/billing/payment-return';

const require = createRequire(
  new URL('../../../../landing/package.json', import.meta.url),
);
const { PGlite } = require('@electric-sql/pglite');
type Query = {
  query: (statement: string, args: unknown[]) => Promise<{ rows: unknown[] }>;
};
function postgres(query: Query) {
  return async (parts: TemplateStringsArray, ...args: unknown[]) => {
    const statement = parts.reduce(
      (s, value, i) => s + (i ? '$' + i : '') + value,
      '',
    );
    return (await query.query(statement, args)).rows;
  };
}
test('account quotas, independent resets and one-time return from test checkout', async (t) => {
  const originalSecret = process.env.AUTH_SECRET;
  process.env.AUTH_SECRET = randomBytes(32).toString('base64url');
  const db = new PGlite();
  try {
    const client = Object.assign(postgres(db), {
      begin: (fn: (sql: ReturnType<typeof postgres>) => Promise<unknown>) =>
        db.transaction((tx: Query) => fn(postgres(tx))),
    });
    t.mock.method(DatabaseConnectionProvider.prototype, 'get', () => ({
      client,
    }));
    await db.exec(
      'CREATE SCHEMA billing; CREATE TABLE billing.payments(id uuid primary key,user_id uuid,plan text,test boolean,status text,card_id uuid); CREATE TABLE billing.test_subscriptions(user_id uuid,plan text,valid_until timestamptz); CREATE TABLE billing.subscriptions(user_id uuid,plan text,status text,valid_until timestamptz)',
    );
    await db.exec(
      await readFile(
        new URL(
          '../../packages/database/migrations/0008_usage_and_payment_returns.sql',
          import.meta.url,
        ),
        'utf8',
      ),
    );
    await db.exec(await readFile(new URL(
      '../../packages/database/migrations/0009_payment_return_platform.sql', import.meta.url,
    ), 'utf8'));
    const owner = randomUUID(),
      other = randomUUID(),
      payment = randomUUID();
    const invite = randomBytes(32).toString('base64url'),
      verifier = randomBytes(32).toString('base64url');
    const hash = (s: string) =>
      createHash('sha256').update(s).digest('base64url');
    process.env.BLOT_TEST_INVITATION_DIGEST = hash(invite);
    const attempt = await startPaymentReturn(owner, hash(verifier), invite, 'macos');
    const legacy = await startPaymentReturn(other, hash(verifier), invite);
    const legacyQuery = await db.query('SELECT platform FROM billing.payment_returns WHERE id=$1', [legacy]);
    assert.equal(legacyQuery.rows[0].platform, 'ios');
    assert.equal((await usageOverview(other)).enforced, false);
    assert.equal((await usageOverview(owner)).enforced, true);
    await db.query(
      "INSERT INTO billing.payments VALUES($1,$2,'premium',true,'pending')",
      [payment, owner],
    );
    assert.equal(await bindPayment(other, attempt, payment), false);
    assert.ok(await bindPayment(owner, attempt, payment));
    assert.equal(await issuePaymentReturn(owner, payment), null);
    await db.query(
      "UPDATE billing.payments SET status='succeeded' WHERE id=$1",
      [payment],
    );
    const expired = await issuePaymentReturn(owner, payment);
    assert.ok(expired);
    await db.query(
      "UPDATE billing.payment_returns SET code_expires_at=now()-interval '1 second' WHERE id=$1",
      [attempt],
    );
    assert.equal(
      await redeemPaymentReturn(owner, attempt, expired.code, verifier),
      undefined,
    );
    const returned = await issuePaymentReturn(owner, payment);
    assert.ok(returned);
    assert.equal(returned.platform, 'macos');
    assert.match(returned.code, /^[A-Za-z0-9_-]{43}$/);
    assert.notEqual(returned.code, expired.code);
    const privateId = createHmac('sha256', process.env.AUTH_SECRET)
      .update('blot/billing/account/v1\0')
      .update(owner)
      .digest('base64url');
    assert.ok(!JSON.stringify(returned).includes(privateId));
    assert.ok(!JSON.stringify(returned).includes(owner));
    assert.equal(
      await redeemPaymentReturn(other, attempt, returned.code, verifier),
      undefined,
    );
    assert.equal(
      await redeemPaymentReturn(owner, attempt, returned.code, invite),
      undefined,
    );
    assert.equal(
      (await redeemPaymentReturn(owner, attempt, returned.code, verifier))
        ?.plan,
      'premium',
    );
    assert.equal(
      await redeemPaymentReturn(owner, attempt, returned.code, verifier),
      undefined,
    );
    const results = await Promise.allSettled([
      reserveUsage(owner, 70000),
      reserveUsage(owner, 70000),
    ]);
    const booked = results.find((x) => x.status === 'fulfilled');
    assert.ok(booked?.status === 'fulfilled');
    assert.ok(
      results.some(
        (x) => x.status === 'rejected' && x.reason instanceof QuotaExceeded,
      ),
    );
    await settleUsage(owner, booked.value, 40000);
    await settleUsage(owner, booked.value, 1000);
    const used = await usageOverview(owner);
    assert.deepEqual(
      used.windows.map((w) => w.percent),
      [40, 10],
    );
    await db.query(
      "UPDATE billing.usage_windows SET starts_at=now()-interval '6 hours' WHERE user_id=$1 AND hours=5",
      [owner],
    );
    assert.deepEqual(
      (await usageOverview(owner)).windows.map((w) => w.percent),
      [0, 10],
    );
    await db.query(
      "INSERT INTO billing.test_subscriptions VALUES($1,'premium',now()+interval '1 month')",
      [owner],
    );
    const paid = await usageOverview(owner);
    assert.ok(paid.test);
    assert.equal(paid.windows[1].percent, 3);
    assert.deepEqual(paid.windows[1].resetsAt, used.windows[1].resetsAt);
    await db.query(
      "UPDATE billing.usage_windows SET starts_at=now()-interval '8 days' WHERE user_id=$1",
      [owner],
    );
    assert.deepEqual(
      (await usageOverview(owner)).windows.map((w) => w.resetsAt),
      [null, null],
    );
    const next = await reserveUsage(owner, 12500);
    await settleUsage(owner, next, 12500);
    assert.deepEqual(
      (await usageOverview(owner)).windows.map((w) => w.percent),
      [5, 1],
    );
  } finally {
    if (originalSecret === undefined) delete process.env.AUTH_SECRET;
    else process.env.AUTH_SECRET = originalSecret;
    delete process.env.BLOT_TEST_INVITATION_DIGEST;
    await db.close();
  }
});
