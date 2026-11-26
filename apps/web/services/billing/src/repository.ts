import type { PaidPlan, PaymentStatus, Plan } from '@teya/contracts';
import {
  DatabaseConnectionProvider,
  type PaymentRow,
  type PlanRow,
  payments,
  plans,
  subscriptions,
  testSubscriptions,
  webhookEvents,
} from '@teya/database';
import { and, desc, eq, inArray, sql } from 'drizzle-orm';

export interface CreatePendingPayment {
  cardId?: string;
  amountMinor: number;
  currency: string;
  id: string;
  idempotencyKey: string;
  plan: PaidPlan;
  userId: string;
}

export interface ApplyProviderPayment {
  confirmationUrl: string | null;
  paymentId: string;
  providerPaymentId: string;
  providerPayload: unknown;
  status: PaymentStatus;
}

export interface CompleteProviderEvent {
  event: string;
  eventKey: string;
  payment: PaymentRow;
  providerPayload: unknown;
  status: PaymentStatus;
}

export interface BillingRepository {
  listPayments(userId: string): Promise<PaymentRow[]>;
  findPaymentByCardId(
    userId: string,
    cardId: string,
  ): Promise<PaymentRow | undefined>;
  applyProviderPayment(input: ApplyProviderPayment): Promise<PaymentRow>;
  cancelSubscription(userId: string): Promise<void>;
  completeProviderEvent(input: CompleteProviderEvent): Promise<boolean>;
  createPendingPayment(input: CreatePendingPayment): Promise<PaymentRow>;
  deleteUserData(userId: string): Promise<void>;
  findPaymentById(id: string): Promise<PaymentRow | undefined>;
  findPaymentByIdempotencyKey(
    idempotencyKey: string,
  ): Promise<PaymentRow | undefined>;
  findPaymentByProviderId(
    providerPaymentId: string,
  ): Promise<PaymentRow | undefined>;
  getPlan(plan: PaidPlan): Promise<PlanRow | undefined>;
  getSubscription(userId: string): Promise<Plan>;
}

export class PostgresBillingRepository implements BillingRepository {
  private readonly db = new DatabaseConnectionProvider().get().db;

  async listPayments(userId: string): Promise<PaymentRow[]> {
    return this.db
      .select()
      .from(payments)
      .where(eq(payments.userId, userId))
      .orderBy(desc(payments.createdAt))
      .limit(100);
  }

  async applyProviderPayment(input: ApplyProviderPayment): Promise<PaymentRow> {
    const [updated] = await this.db
      .update(payments)
      .set({
        confirmationUrl: input.confirmationUrl,
        providerPaymentId: input.providerPaymentId,
        providerPayload: input.providerPayload,
        status: input.status,
        updatedAt: new Date(),
      })
      .where(eq(payments.id, input.paymentId))
      .returning();
    if (!updated) {
      throw new Error('Payment update returned no row');
    }
    return updated;
  }

  async cancelSubscription(userId: string): Promise<void> {
    await this.db
      .insert(subscriptions)
      .values({
        plan: 'free',
        status: 'active',
        userId,
      })
      .onConflictDoUpdate({
        set: {
          plan: 'free',
          sourcePaymentId: null,
          status: 'active',
          updatedAt: new Date(),
          validUntil: null,
        },
        target: subscriptions.userId,
      });
  }

  async completeProviderEvent(input: CompleteProviderEvent): Promise<boolean> {
    return this.db.transaction(async (transaction) => {
      const [current] = await transaction
        .select()
        .from(payments)
        .where(eq(payments.id, input.payment.id))
        .for('update');
      if (!current) throw new Error('Payment not found');
      if (
        (current.status === 'succeeded' || current.status === 'canceled') &&
        current.status !== input.status
      )
        return false;
      const insertedEvents = await transaction
        .insert(webhookEvents)
        .values({
          event: input.event,
          eventKey: input.eventKey,
          payload: input.providerPayload,
          providerPaymentId: input.payment.providerPaymentId ?? '',
        })
        .onConflictDoNothing({ target: webhookEvents.eventKey })
        .returning({ id: webhookEvents.id });
      if (insertedEvents.length === 0) {
        return false;
      }

      await transaction
        .update(payments)
        .set({
          providerPayload: input.providerPayload,
          status: input.status,
          updatedAt: new Date(),
        })
        .where(eq(payments.id, input.payment.id));

      if (input.status === 'succeeded' && input.payment.test) {
        const validUntil = new Date();
        const day = validUntil.getUTCDate();
        validUntil.setUTCDate(1);
        validUntil.setUTCMonth(validUntil.getUTCMonth() + 1);
        const lastDay = new Date(
          Date.UTC(
            validUntil.getUTCFullYear(),
            validUntil.getUTCMonth() + 1,
            0,
          ),
        ).getUTCDate();
        validUntil.setUTCDate(Math.min(day, lastDay));
        await transaction
          .insert(testSubscriptions)
          .values({
            userId: input.payment.userId,
            plan: input.payment.plan,
            sourcePaymentId: input.payment.id,
            validUntil,
          })
          .onConflictDoUpdate({
            target: testSubscriptions.userId,
            set: {
              plan: input.payment.plan,
              sourcePaymentId: input.payment.id,
              validUntil,
            },
          });
      } else if (input.status === 'succeeded') {
        await transaction
          .insert(subscriptions)
          .values({
            plan: input.payment.plan,
            sourcePaymentId: input.payment.id,
            status: 'active',
            userId: input.payment.userId,
          })
          .onConflictDoUpdate({
            set: {
              plan: input.payment.plan,
              sourcePaymentId: input.payment.id,
              status: 'active',
              updatedAt: new Date(),
            },
            target: subscriptions.userId,
          });
      }

      return true;
    });
  }

  async createPendingPayment(input: CreatePendingPayment): Promise<PaymentRow> {
    const [created] = await this.db
      .insert(payments)
      .values({
        cardId: input.cardId,
        test: true,
        amountMinor: input.amountMinor,
        currency: input.currency,
        id: input.id,
        idempotencyKey: input.idempotencyKey,
        plan: input.plan,
        userId: input.userId,
      })
      .returning();
    if (!created) {
      throw new Error('Payment creation returned no row');
    }
    return created;
  }

  async deleteUserData(userId: string): Promise<void> {
    await this.db.transaction(async (transaction) => {
      const userPayments = await transaction
        .select({ providerPaymentId: payments.providerPaymentId })
        .from(payments)
        .where(eq(payments.userId, userId));
      const providerPaymentIds = userPayments.flatMap((payment) =>
        payment.providerPaymentId ? [payment.providerPaymentId] : [],
      );
      if (providerPaymentIds.length > 0) {
        await transaction
          .delete(webhookEvents)
          .where(inArray(webhookEvents.providerPaymentId, providerPaymentIds));
      }
      await transaction
        .delete(subscriptions)
        .where(eq(subscriptions.userId, userId));
      await transaction
        .delete(testSubscriptions)
        .where(eq(testSubscriptions.userId, userId));
      await transaction.execute(
        sql`DELETE FROM billing.payment_returns WHERE user_id=${userId}`,
      );
      await transaction.execute(
        sql`DELETE FROM billing.usage_reservations WHERE user_id=${userId}`,
      );
      await transaction.execute(
        sql`DELETE FROM billing.usage_windows WHERE user_id=${userId}`,
      );
      await transaction.execute(
        sql`DELETE FROM billing.quota_pilots WHERE user_id=${userId}`,
      );
      await transaction.delete(payments).where(eq(payments.userId, userId));
    });
  }

  async findPaymentByCardId(
    userId: string,
    cardId: string,
  ): Promise<PaymentRow | undefined> {
    const [payment] = await this.db
      .select()
      .from(payments)
      .where(and(eq(payments.userId, userId), eq(payments.cardId, cardId)))
      .orderBy(desc(payments.createdAt))
      .limit(1);
    return payment;
  }

  async findPaymentById(id: string): Promise<PaymentRow | undefined> {
    const [payment] = await this.db
      .select()
      .from(payments)
      .where(eq(payments.id, id))
      .limit(1);
    return payment;
  }

  async findPaymentByIdempotencyKey(
    idempotencyKey: string,
  ): Promise<PaymentRow | undefined> {
    const [payment] = await this.db
      .select()
      .from(payments)
      .where(eq(payments.idempotencyKey, idempotencyKey))
      .limit(1);
    return payment;
  }

  async findPaymentByProviderId(
    providerPaymentId: string,
  ): Promise<PaymentRow | undefined> {
    const [payment] = await this.db
      .select()
      .from(payments)
      .where(eq(payments.providerPaymentId, providerPaymentId))
      .limit(1);
    return payment;
  }

  async getPlan(plan: PaidPlan): Promise<PlanRow | undefined> {
    const [selected] = await this.db
      .select()
      .from(plans)
      .where(and(eq(plans.id, plan), eq(plans.active, true)))
      .limit(1);
    return selected;
  }

  async getSubscription(userId: string): Promise<Plan> {
    const [subscription] = await this.db
      .select({
        plan: subscriptions.plan,
        validUntil: subscriptions.validUntil,
      })
      .from(subscriptions)
      .where(eq(subscriptions.userId, userId))
      .limit(1);
    if (subscription?.validUntil && subscription.validUntil <= new Date())
      return 'free';
    if (
      subscription &&
      ['premium', 'super', 'ultra', 'team'].includes(subscription.plan)
    ) {
      return subscription.plan as Plan;
    }
    return 'free';
  }
}
