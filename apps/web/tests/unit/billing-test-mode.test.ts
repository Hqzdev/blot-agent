import assert from 'node:assert/strict';
import test from 'node:test';
import { subscriptionCatalog } from '@teya/contracts';
import { YooKassaClient } from '@teya/service-billing';

test('public catalog has the three approved monthly RUB prices', () => {
  assert.deepEqual(
    subscriptionCatalog.map(({ plan, amountMinor }) => [plan, amountMinor]),
    [
      ['premium', 250000],
      ['super', 500000],
      ['ultra', 1000000],
    ],
  );
});

test('YooKassa parser rejects a live payment even with test credentials', async () => {
  const fetch = globalThis.fetch;
  globalThis.fetch = async () =>
    Response.json({
      id: 'payment',
      amount: { currency: 'RUB', value: '2500.00' },
      paid: false,
      test: false,
      status: 'pending',
    });
  try {
    await assert.rejects(
      new YooKassaClient('shop', 'test_secret', 1).getPayment('payment'),
    );
  } finally {
    globalThis.fetch = fetch;
  }
});

test('YooKassa payment result preserves verified test mode', async () => {
  const fetch = globalThis.fetch;
  globalThis.fetch = async () =>
    Response.json({
      id: 'payment',
      amount: { currency: 'RUB', value: '10000.00' },
      paid: false,
      test: true,
      status: 'pending',
    });
  try {
    const payment = await new YooKassaClient(
      'shop',
      'test_secret',
      1,
    ).getPayment('payment');
    assert.equal(payment.test, true);
    assert.equal(payment.amountMinor, 1000000);
  } finally {
    globalThis.fetch = fetch;
  }
});

test('checkout verifies the shop before creating any payment', async () => {
  const fetch = globalThis.fetch;
  const requests: string[] = [];
  globalThis.fetch = async (input) => {
    requests.push(String(input));
    return Response.json({ account_id: 'shop', test: false });
  };
  try {
    await assert.rejects(
      new YooKassaClient('shop', 'test_secret', 1).createPayment({
        amountMinor: 250000,
        currency: 'RUB',
        customerEmail: 'owner@example.com',
        idempotencyKey: 'key',
        localPaymentId: 'payment',
        plan: 'premium',
        returnUrl: 'https://blot.example/app/payment/success',
        userId: 'owner',
      }),
    );
    assert.deepEqual(requests, ['https://api.yookassa.ru/v3/me']);
  } finally {
    globalThis.fetch = fetch;
  }
});
