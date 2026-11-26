import { randomUUID } from 'node:crypto';

import {
  type CheckoutResponse,
  type PaidPlan,
  type PaymentStatus,
  type PaymentStatusResponse,
  type Plan,
  type YooKassaNotification,
  subscriptionCatalog,
} from '@teya/contracts';

import {
  BillingConflictError,
  BillingForbiddenError,
  BillingNotFoundError,
  BillingValidationError,
} from './errors';
import type { PaymentProvider, ProviderPayment } from './provider';
import type { BillingRepository } from './repository';

export class BillingService {
  constructor(
    private readonly repository: BillingRepository,
    private readonly provider: PaymentProvider,
  ) {}

  async createCheckout(input: {
    cardId?: string;
    customerEmail: string;
    idempotencyKey: string;
    plan: PaidPlan;
    returnUrl: string;
    userId: string;
  }): Promise<CheckoutResponse> {
    const tier = subscriptionCatalog.find((tier) => tier.plan === input.plan);
    if (!tier)
      throw new BillingValidationError(
        'Plan is no longer available for checkout',
      );
    const existing = await this.repository.findPaymentByIdempotencyKey(
      input.idempotencyKey,
    );
    if (existing) {
      this.requirePaymentOwner(existing.userId, input.userId);
      if (
        existing.plan !== input.plan ||
        (existing.cardId ?? undefined) !== input.cardId
      ) {
        throw new BillingConflictError(
          'Idempotency key belongs to another plan',
        );
      }
      if (!existing.test)
        throw new BillingConflictError(
          'Live payment cannot be reused in test mode',
        );
      if (existing.confirmationUrl) {
        return {
          confirmationUrl: existing.confirmationUrl,
          paymentId: existing.id,
          status: this.toPaymentStatus(existing.status),
        };
      }
    }

    const plan = await this.repository.getPlan(input.plan);
    if (
      !plan ||
      plan.amountMinor !== tier.amountMinor ||
      plan.currency !== 'RUB'
    ) {
      throw new BillingValidationError('Plan is not available');
    }

    const localPayment =
      existing ??
      (await this.repository.createPendingPayment({
        cardId: input.cardId,
        amountMinor: plan.amountMinor,
        currency: plan.currency,
        id: randomUUID(),
        idempotencyKey: input.idempotencyKey,
        plan: input.plan,
        userId: input.userId,
      }));

    const providerPayment = await this.provider.createPayment({
      amountMinor: localPayment.amountMinor,
      currency: localPayment.currency,
      customerEmail: input.customerEmail,
      idempotencyKey: input.idempotencyKey,
      localPaymentId: localPayment.id,
      plan: input.plan,
      returnUrl: input.returnUrl,
      userId: input.userId,
    });
    this.validateProviderPayment(localPayment, providerPayment);
    if (!providerPayment.confirmationUrl) {
      throw new BillingValidationError(
        'Payment provider returned no confirmation URL',
      );
    }

    const updated = await this.repository.applyProviderPayment({
      confirmationUrl: providerPayment.confirmationUrl,
      paymentId: localPayment.id,
      providerPaymentId: providerPayment.id,
      providerPayload: providerPayment.raw,
      status: providerPayment.status,
    });
    return {
      confirmationUrl: providerPayment.confirmationUrl,
      paymentId: updated.id,
      status: providerPayment.status,
    };
  }

  async getCardPaymentStatus(
    userId: string,
    cardId: string,
  ): Promise<PaymentStatusResponse> {
    const payment = await this.repository.findPaymentByCardId(userId, cardId);
    if (!payment) throw new BillingNotFoundError('Payment not found');
    return this.getPaymentStatus(userId, payment.id);
  }

  async getPaymentStatus(
    userId: string,
    paymentId: string,
  ): Promise<PaymentStatusResponse> {
    const payment = await this.repository.findPaymentById(paymentId);
    if (!payment) {
      throw new BillingNotFoundError('Payment not found');
    }
    this.requirePaymentOwner(payment.userId, userId);
    if (
      payment.test &&
      payment.providerPaymentId &&
      (payment.status === 'pending' || payment.status === 'waiting_for_capture')
    ) {
      await this.processNotification({
        type: 'notification',
        event: 'payment.succeeded',
        object: { id: payment.providerPaymentId },
      });
      const refreshed = await this.repository.findPaymentById(paymentId);
      if (refreshed)
        return {
          cardId: refreshed.cardId ?? undefined,
          paymentId: refreshed.id,
          plan: this.toPaidPlan(refreshed.plan),
          status: this.toPaymentStatus(refreshed.status),
          test: true,
        };
    }
    return {
      cardId: payment.cardId ?? undefined,
      test: payment.test,
      paymentId: payment.id,
      plan: this.toPaidPlan(payment.plan),
      status: this.toPaymentStatus(payment.status),
    };
  }

  async getPaymentHistory(userId: string) {
    return (await this.repository.listPayments(userId)).map((payment) => ({
      paymentId: payment.id,
      plan: this.toPaidPlan(payment.plan),
      amountMinor: payment.amountMinor,
      currency: payment.currency,
      status: this.toPaymentStatus(payment.status),
      test: payment.test,
      createdAt: payment.createdAt.toISOString(),
    }));
  }

  getSubscription(userId: string): Promise<Plan> {
    return this.repository.getSubscription(userId);
  }

  cancelSubscription(userId: string): Promise<void> {
    return this.repository.cancelSubscription(userId);
  }

  deleteUserData(userId: string): Promise<void> {
    return this.repository.deleteUserData(userId);
  }

  async processNotification(
    notification: YooKassaNotification,
  ): Promise<boolean> {
    const providerPayment = await this.provider.getPayment(
      notification.object.id,
    );
    const localPayment = await this.resolveLocalPayment(providerPayment);
    this.validateProviderPayment(localPayment, providerPayment);
    const expectedEvent = `payment.${providerPayment.status}`;
    if (providerPayment.status === 'succeeded' && !providerPayment.paid) {
      throw new BillingValidationError('Succeeded payment is not paid');
    }

    return this.repository.completeProviderEvent({
      event: expectedEvent,
      eventKey: `${providerPayment.id}:${providerPayment.status}`,
      payment: localPayment,
      providerPayload: providerPayment.raw,
      status: providerPayment.status,
    });
  }

  private async resolveLocalPayment(providerPayment: ProviderPayment) {
    const byProvider = await this.repository.findPaymentByProviderId(
      providerPayment.id,
    );
    if (byProvider) {
      return byProvider;
    }
    const localPaymentId = providerPayment.metadata.localPaymentId;
    if (!localPaymentId) {
      throw new BillingNotFoundError('Payment metadata is missing');
    }
    const byLocalId = await this.repository.findPaymentById(localPaymentId);
    if (!byLocalId) {
      throw new BillingNotFoundError('Local payment not found');
    }
    this.validateProviderPayment(byLocalId, providerPayment);
    return this.repository.applyProviderPayment({
      confirmationUrl: providerPayment.confirmationUrl,
      paymentId: byLocalId.id,
      providerPaymentId: providerPayment.id,
      providerPayload: providerPayment.raw,
      status: providerPayment.status,
    });
  }

  private validateProviderPayment(
    localPayment: {
      amountMinor: number;
      currency: string;
      id: string;
      plan: string;
      userId: string;
      test: boolean;
    },
    providerPayment: ProviderPayment,
  ): void {
    if (
      localPayment.test !== true ||
      providerPayment.test !== true ||
      localPayment.amountMinor !== providerPayment.amountMinor ||
      localPayment.currency !== providerPayment.currency ||
      localPayment.id !== providerPayment.metadata.localPaymentId ||
      localPayment.plan !== providerPayment.metadata.plan ||
      localPayment.userId !== providerPayment.metadata.userId
    ) {
      throw new BillingValidationError('Provider payment data mismatch');
    }
  }

  private requirePaymentOwner(
    paymentUserId: string,
    actorUserId: string,
  ): void {
    if (paymentUserId !== actorUserId) {
      throw new BillingForbiddenError('Payment access is forbidden');
    }
  }

  private toPaidPlan(plan: string): PaidPlan {
    if (
      plan === 'premium' ||
      plan === 'super' ||
      plan === 'ultra' ||
      plan === 'team'
    ) {
      return plan;
    }
    throw new BillingValidationError('Payment contains an invalid plan');
  }

  private toPaymentStatus(status: string): PaymentStatus {
    if (
      status === 'pending' ||
      status === 'waiting_for_capture' ||
      status === 'succeeded' ||
      status === 'canceled'
    ) {
      return status;
    }
    throw new BillingValidationError('Payment contains an invalid status');
  }
}
