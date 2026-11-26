import 'server-only';

import type {
  BillingHistoryItem,
  CheckoutResponse,
  PaidPlan,
  PaymentStatusResponse,
  Plan,
} from '@teya/contracts';
import { InternalApiClient } from '@teya/platform';
import {
  BillingService,
  PaymentProviderFactory,
  PostgresBillingRepository,
} from '@teya/service-billing';

interface RpcResponse<T> {
  result: T;
}

export interface BillingGateway {
  getPaymentHistory(userId: string): Promise<BillingHistoryItem[]>;
  getCardPaymentStatus(
    userId: string,
    cardId: string,
  ): Promise<PaymentStatusResponse>;
  cancelSubscription(userId: string): Promise<void>;
  createCheckout(input: {
    cardId?: string;
    customerEmail: string;
    idempotencyKey: string;
    plan: PaidPlan;
    returnUrl: string;
    userId: string;
  }): Promise<CheckoutResponse>;
  deleteUserData(userId: string): Promise<void>;
  getPaymentStatus(
    userId: string,
    paymentId: string,
  ): Promise<PaymentStatusResponse>;
  getSubscription(userId: string): Promise<Plan>;
}

class LocalBillingGateway implements BillingGateway {
  getPaymentHistory(userId: string) {
    return this.getService().getPaymentHistory(userId);
  }
  private service: BillingService | undefined;
  private readonly repository = new PostgresBillingRepository();

  getCardPaymentStatus(
    userId: string,
    cardId: string,
  ): Promise<PaymentStatusResponse> {
    return this.getService().getCardPaymentStatus(userId, cardId);
  }
  cancelSubscription(userId: string): Promise<void> {
    return this.getService().cancelSubscription(userId);
  }

  createCheckout(input: {
    cardId?: string;
    customerEmail: string;
    idempotencyKey: string;
    plan: PaidPlan;
    returnUrl: string;
    userId: string;
  }): Promise<CheckoutResponse> {
    return this.getService().createCheckout(input);
  }

  deleteUserData(userId: string): Promise<void> {
    return this.repository.deleteUserData(userId);
  }

  getPaymentStatus(
    userId: string,
    paymentId: string,
  ): Promise<PaymentStatusResponse> {
    return this.getService().getPaymentStatus(userId, paymentId);
  }

  getSubscription(userId: string): Promise<Plan> {
    return this.repository.getSubscription(userId);
  }

  private getService(): BillingService {
    if (!this.service) {
      this.service = new BillingService(
        this.repository,
        new PaymentProviderFactory().create(process.env),
      );
    }
    return this.service;
  }
}

class HttpBillingGateway implements BillingGateway {
  getPaymentHistory(userId: string): Promise<BillingHistoryItem[]> {
    return this.call(userId, { operation: 'getPaymentHistory', payload: {} });
  }
  getCardPaymentStatus(
    userId: string,
    cardId: string,
  ): Promise<PaymentStatusResponse> {
    return this.call(userId, {
      operation: 'getCardPaymentStatus',
      payload: { cardId },
    });
  }
  private readonly client: InternalApiClient;

  constructor(baseUrl: string, secret: string) {
    this.client = new InternalApiClient(baseUrl, secret);
  }

  async cancelSubscription(userId: string): Promise<void> {
    await this.call(userId, {
      operation: 'cancelSubscription',
      payload: {},
    });
  }

  createCheckout(input: {
    cardId?: string;
    customerEmail: string;
    idempotencyKey: string;
    plan: PaidPlan;
    returnUrl: string;
    userId: string;
  }): Promise<CheckoutResponse> {
    return this.call(input.userId, {
      operation: 'createCheckout',
      payload: {
        cardId: input.cardId,
        customerEmail: input.customerEmail,
        idempotencyKey: input.idempotencyKey,
        plan: input.plan,
        returnUrl: input.returnUrl,
      },
    });
  }

  async deleteUserData(userId: string): Promise<void> {
    await this.call('system:web', {
      operation: 'deleteUserData',
      payload: { userId },
    });
  }

  getPaymentStatus(
    userId: string,
    paymentId: string,
  ): Promise<PaymentStatusResponse> {
    return this.call(userId, {
      operation: 'getPaymentStatus',
      payload: { paymentId },
    });
  }

  getSubscription(userId: string): Promise<Plan> {
    return this.call(userId, {
      operation: 'getSubscription',
      payload: {},
    });
  }

  private async call<T>(actorId: string, body: unknown): Promise<T> {
    const response = await this.client.request<RpcResponse<T>>({
      actorId,
      body,
      path: '/api/rpc',
    });
    return response.result;
  }
}

let billingGateway: BillingGateway | undefined;

export function getBillingGateway(): BillingGateway {
  if (billingGateway) {
    return billingGateway;
  }
  const serviceUrl = process.env.BILLING_SERVICE_URL;
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  billingGateway =
    serviceUrl && secret
      ? new HttpBillingGateway(serviceUrl, secret)
      : new LocalBillingGateway();
  return billingGateway;
}
