import type { PaidPlan, PaymentStatus } from '@teya/contracts';
import { z } from 'zod';

import { BillingProviderError } from './errors';

const yooKassaPaymentSchema = z.object({
  amount: z.object({
    currency: z.string(),
    value: z.string(),
  }),
  confirmation: z
    .object({
      confirmation_url: z.string().url().optional(),
      type: z.string(),
    })
    .optional(),
  id: z.string(),
  metadata: z.record(z.string()).default({}),
  paid: z.boolean(),
  test: z.literal(true),
  status: z.enum(['pending', 'waiting_for_capture', 'succeeded', 'canceled']),
});

export interface ProviderPayment {
  amountMinor: number;
  confirmationUrl: string | null;
  currency: string;
  id: string;
  metadata: Record<string, string>;
  paid: boolean;
  test: boolean;
  raw: unknown;
  status: PaymentStatus;
}

export interface CreateProviderPayment {
  amountMinor: number;
  currency: string;
  customerEmail: string;
  idempotencyKey: string;
  localPaymentId: string;
  plan: PaidPlan;
  returnUrl: string;
  userId: string;
}

export interface PaymentProvider {
  createPayment(input: CreateProviderPayment): Promise<ProviderPayment>;
  getPayment(providerPaymentId: string): Promise<ProviderPayment>;
}

export class YooKassaClient implements PaymentProvider {
  private readonly endpoint = 'https://api.yookassa.ru/v3';
  private readonly authorization: string;
  private testShopVerified = false;

  constructor(
    private readonly shopId: string,
    secretKey: string,
    private readonly vatCode: number,
  ) {
    if (!secretKey.startsWith('test_'))
      throw new BillingProviderError('Test YooKassa key is required');
    this.authorization = `Basic ${Buffer.from(`${shopId}:${secretKey}`).toString('base64')}`;
  }

  async createPayment(input: CreateProviderPayment): Promise<ProviderPayment> {
    await this.verifyTestShop();
    const description = `Ori ${input.plan} · тестовый платёж`;
    const response = await fetch(`${this.endpoint}/payments`, {
      body: JSON.stringify({
        amount: {
          currency: input.currency,
          value: this.toMajorUnits(input.amountMinor),
        },
        capture: true,
        confirmation: {
          return_url: input.returnUrl,
          type: 'redirect',
        },
        description,
        metadata: {
          localPaymentId: input.localPaymentId,
          plan: input.plan,
          userId: input.userId,
        },
        receipt: {
          customer: {
            email: input.customerEmail,
          },
          items: [
            {
              amount: {
                currency: input.currency,
                value: this.toMajorUnits(input.amountMinor),
              },
              description,
              payment_mode: 'full_payment',
              payment_subject: 'service',
              quantity: '1.00',
              vat_code: this.vatCode,
            },
          ],
        },
      }),
      headers: {
        authorization: this.authorization,
        'content-type': 'application/json',
        'idempotence-key': input.idempotencyKey,
      },
      method: 'POST',
      signal: AbortSignal.timeout(15000),
    });
    return this.parseResponse(response);
  }

  async getPayment(providerPaymentId: string): Promise<ProviderPayment> {
    const response = await fetch(
      `${this.endpoint}/payments/${encodeURIComponent(providerPaymentId)}`,
      {
        headers: {
          authorization: this.authorization,
        },
        signal: AbortSignal.timeout(15000),
      },
    );
    return this.parseResponse(response);
  }

  async verifyTestShop(): Promise<void> {
    if (this.testShopVerified) return;
    const response = await fetch(`${this.endpoint}/me`, {
      headers: { authorization: this.authorization },
      signal: AbortSignal.timeout(15000),
    });
    const settings = z
      .object({ account_id: z.string(), test: z.literal(true) })
      .parse(await response.json());
    if (!response.ok || settings.account_id !== this.shopId)
      throw new BillingProviderError('Test shop verification failed');
    this.testShopVerified = true;
  }

  private async parseResponse(response: Response): Promise<ProviderPayment> {
    const raw = await response.json().catch(() => null);
    if (!response.ok) {
      throw new BillingProviderError(
        `YooKassa request failed with ${response.status}`,
      );
    }
    const payment = yooKassaPaymentSchema.parse(raw);
    return {
      amountMinor: Math.round(Number(payment.amount.value) * 100),
      confirmationUrl: payment.confirmation?.confirmation_url ?? null,
      currency: payment.amount.currency,
      id: payment.id,
      metadata: payment.metadata,
      paid: payment.paid,
      test: payment.test,
      raw,
      status: payment.status,
    };
  }

  private toMajorUnits(amountMinor: number): string {
    return (amountMinor / 100).toFixed(2);
  }
}

export class PaymentProviderFactory {
  create(environment: NodeJS.ProcessEnv): YooKassaClient {
    const shopId = environment.YOOKASSA_SHOP_ID;
    const secretKey = environment.YOOKASSA_SECRET_KEY;
    if (!shopId || !secretKey) {
      throw new Error('YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY are required');
    }
    const vatCode = Number(environment.YOOKASSA_VAT_CODE ?? '1');
    if (!Number.isInteger(vatCode) || vatCode < 1 || vatCode > 6) {
      throw new Error('YOOKASSA_VAT_CODE must be an integer from 1 to 6');
    }
    return new YooKassaClient(shopId, secretKey, vatCode);
  }
}
