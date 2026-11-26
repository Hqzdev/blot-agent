import assert from 'node:assert/strict';
import test from 'node:test';

import type { PaidPlan, Plan } from '@teya/contracts';
import type { PaymentRow, PlanRow } from '@teya/database';
import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  type ApplyProviderPayment,
  type BillingRepository,
  BillingRpcController,
  BillingService,
  BillingWebhookController,
  type CompleteProviderEvent,
  type CreatePendingPayment,
  type CreateProviderPayment,
  type PaymentProvider,
  type ProviderPayment,
} from '@teya/service-billing';

const secret = 'a-secure-internal-secret-with-32-characters';
const userId = '11111111-1111-4111-8111-111111111111';
const otherUserId = '22222222-2222-4222-8222-222222222222';
const paymentId = '33333333-3333-4333-8333-333333333333';
const idempotencyKey = '44444444-4444-4444-8444-444444444444';

class BillingRepositoryFake implements BillingRepository {
  readonly payments = new Map<string, PaymentRow>();
  readonly subscriptions = new Map<string, Plan>();
  readonly testSubscriptions = new Map<string, Plan>();
  readonly events = new Set<string>();
  readonly plans = new Map<PaidPlan, PlanRow>([
    [
      'premium',
      {
        active: true,
        amountMinor: 250_000,
        currency: 'RUB',
        id: 'premium',
        name: 'Premium',
      },
    ],
    [
      'team',
      {
        active: true,
        amountMinor: 200_000,
        currency: 'RUB',
        id: 'team',
        name: 'Team',
      },
    ],
  ]);

  async applyProviderPayment(input: ApplyProviderPayment) {
    const current = this.payments.get(input.paymentId);
    assert.ok(current);
    const updated = {
      ...current,
      confirmationUrl: input.confirmationUrl,
      providerPayload: input.providerPayload,
      providerPaymentId: input.providerPaymentId,
      status: input.status,
      updatedAt: new Date(),
    };
    this.payments.set(updated.id, updated);
    return updated;
  }

  async cancelSubscription(id: string) {
    this.subscriptions.set(id, 'free');
  }

  async completeProviderEvent(input: CompleteProviderEvent) {
    if (this.events.has(input.eventKey)) {
      return false;
    }
    this.events.add(input.eventKey);
    this.payments.set(input.payment.id, {
      ...input.payment,
      status: input.status,
      providerPayload: input.providerPayload,
    });
    if (input.status === 'succeeded') {
      this.testSubscriptions.set(
        input.payment.userId,
        input.payment.plan as Plan,
      );
    }
    return true;
  }

  async createPendingPayment(input: CreatePendingPayment) {
    const row: PaymentRow = {
      cardId: input.cardId ?? null,
      test: true,
      amountMinor: input.amountMinor,
      confirmationUrl: null,
      createdAt: new Date(),
      currency: input.currency,
      id: paymentId,
      idempotencyKey: input.idempotencyKey,
      plan: input.plan,
      providerPayload: null,
      providerPaymentId: null,
      status: 'pending',
      updatedAt: new Date(),
      userId: input.userId,
    };
    this.payments.set(row.id, row);
    return row;
  }

  async deleteUserData(id: string) {
    this.subscriptions.delete(id);
  }

  async findPaymentByCardId(id: string, cardId: string) {
    return [...this.payments.values()].find(
      (payment) => payment.userId === id && payment.cardId === cardId,
    );
  }
  async findPaymentById(id: string) {
    return this.payments.get(id);
  }

  async findPaymentByIdempotencyKey(key: string) {
    return [...this.payments.values()].find(
      (payment) => payment.idempotencyKey === key,
    );
  }

  async findPaymentByProviderId(id: string) {
    return [...this.payments.values()].find(
      (payment) => payment.providerPaymentId === id,
    );
  }

  async getPlan(plan: PaidPlan) {
    return this.plans.get(plan);
  }

  async listPayments(id: string) {
    return [...this.payments.values()].filter(
      (payment) => payment.userId === id,
    );
  }

  async getSubscription(id: string) {
    return this.subscriptions.get(id) ?? 'free';
  }
}

class PaymentProviderFake implements PaymentProvider {
  lastCreateInput: CreateProviderPayment | undefined;
  payment: ProviderPayment = {
    test: true,
    amountMinor: 250_000,
    confirmationUrl: 'https://yookassa.example/confirm',
    currency: 'RUB',
    id: 'provider-payment-1',
    metadata: {
      localPaymentId: paymentId,
      plan: 'premium',
      userId,
    },
    paid: false,
    raw: {},
    status: 'pending',
  };

  async createPayment(input: CreateProviderPayment) {
    this.lastCreateInput = input;
    return this.payment;
  }

  async getPayment() {
    return this.payment;
  }
}

function createSignedRequest(
  signer: InternalRequestSigner,
  actorId: string,
  body: unknown,
) {
  const serializedBody = JSON.stringify(body);
  return new Request('https://billing.example/api/rpc', {
    body: serializedBody,
    headers: signer.createHeaders({
      actorId,
      body: serializedBody,
      method: 'POST',
      target: '/api/rpc',
    }),
    method: 'POST',
  });
}

test('billing RPC uses the signed actor and catalog amount', async () => {
  const repository = new BillingRepositoryFake();
  const provider = new PaymentProviderFake();
  const service = new BillingService(repository, provider);
  const signer = new InternalRequestSigner(secret);
  const controller = new BillingRpcController(
    new InternalRequestVerifier(signer),
    service,
  );
  const response = await controller.handle(
    createSignedRequest(signer, userId, {
      operation: 'createCheckout',
      payload: {
        amountMinor: 1,
        customerEmail: 'owner@example.com',
        idempotencyKey,
        plan: 'premium',
        returnUrl: 'https://teya.example/payment/success',
        userId: otherUserId,
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(provider.lastCreateInput?.amountMinor, 250_000);
  assert.equal(provider.lastCreateInput?.userId, userId);
  assert.equal(repository.payments.get(paymentId)?.userId, userId);
});

test('verified YooKassa state activates once and mismatches never activate', async () => {
  const repository = new BillingRepositoryFake();
  const provider = new PaymentProviderFake();
  const service = new BillingService(repository, provider);
  await service.createCheckout({
    customerEmail: 'owner@example.com',
    idempotencyKey,
    plan: 'premium',
    returnUrl: 'https://teya.example/payment/success',
    userId,
  });
  const webhook = new BillingWebhookController(service);
  provider.payment = {
    ...provider.payment,
    amountMinor: 1,
    paid: true,
    status: 'succeeded',
  };
  const forged = await webhook.handle(
    new Request('https://billing.example/api/webhook', {
      body: JSON.stringify({
        event: 'payment.succeeded',
        object: { id: provider.payment.id },
        type: 'notification',
      }),
      method: 'POST',
    }),
  );

  assert.equal(forged.status, 422);
  assert.equal(await repository.getSubscription(userId), 'free');

  provider.payment = {
    ...provider.payment,
    amountMinor: 250_000,
  };
  const legitimateRequest = () =>
    new Request('https://billing.example/api/webhook', {
      body: JSON.stringify({
        event: 'payment.succeeded',
        object: { id: provider.payment.id },
        type: 'notification',
      }),
      method: 'POST',
    });
  const first = await webhook.handle(legitimateRequest());
  const second = await webhook.handle(legitimateRequest());

  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(await repository.getSubscription(userId), 'free');
  assert.equal(repository.testSubscriptions.get(userId), 'premium');
  assert.equal(repository.events.size, 1);
});

test('native payment cards are owner-bound and refresh provider state without a webhook', async () => {
  const repository = new BillingRepositoryFake();
  const provider = new PaymentProviderFake();
  const service = new BillingService(repository, provider);
  const cardId = '55555555-5555-4555-8555-555555555555';
  await service.createCheckout({
    customerEmail: 'owner@example.com',
    idempotencyKey,
    plan: 'premium',
    returnUrl: 'https://blot.example/app/payment/success',
    userId,
    cardId,
  });
  await assert.rejects(service.getCardPaymentStatus(otherUserId, cardId));
  provider.payment = { ...provider.payment, status: 'succeeded', paid: true };
  const status = await service.getCardPaymentStatus(userId, cardId);
  assert.equal(status.status, 'succeeded');
  assert.equal(status.test, true);
  assert.equal(status.cardId, cardId);
  assert.equal(await repository.getSubscription(userId), 'free');
  assert.equal(repository.testSubscriptions.get(userId), 'premium');
});

test('canceled checkout never activates a test or live subscription', async () => {
  const repository = new BillingRepositoryFake();
  const provider = new PaymentProviderFake();
  const service = new BillingService(repository, provider);
  await service.createCheckout({
    customerEmail: 'owner@example.com',
    idempotencyKey,
    plan: 'premium',
    returnUrl: 'https://blot.example/app/payment/success',
    userId,
  });
  provider.payment = { ...provider.payment, status: 'canceled' };
  assert.equal(
    (await service.getPaymentStatus(userId, paymentId)).status,
    'canceled',
  );
  assert.equal(await repository.getSubscription(userId), 'free');
  assert.equal(repository.testSubscriptions.size, 0);
});

test('payment history is owner-scoped and excludes provider secrets', async () => {
  const repository = new BillingRepositoryFake();
  const service = new BillingService(repository, new PaymentProviderFake());
  await service.createCheckout({
    customerEmail: 'owner@example.com',
    idempotencyKey,
    plan: 'premium',
    returnUrl: 'https://blot.example/app/payment/success',
    userId,
  });
  const history = await service.getPaymentHistory(userId);
  assert.equal(history.length, 1);
  assert.equal(history[0].amountMinor, 250_000);
  assert.equal(history[0].test, true);
  assert.equal('providerPayload' in history[0], false);
  assert.equal('confirmationUrl' in history[0], false);
  assert.deepEqual(await service.getPaymentHistory(otherUserId), []);
});
