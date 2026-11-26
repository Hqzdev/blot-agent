import { z } from 'zod';
import catalog from '../../../../../contracts/subscription-plans.json';

export const planSchema = z.enum(['free', 'premium', 'super', 'ultra', 'team']);
export const paidPlanSchema = z.enum(['premium', 'super', 'ultra', 'team']);
export const paymentStatusSchema = z.enum([
  'pending',
  'waiting_for_capture',
  'succeeded',
  'canceled',
]);

export const createCheckoutSchema = z.object({
  cardId: z.string().uuid().optional(),
  idempotencyKey: z.string().uuid(),
  plan: paidPlanSchema,
  returnUrl: z.string().url(),
});

export const checkoutResponseSchema = z.object({
  confirmationUrl: z.string().url(),
  paymentId: z.string().uuid(),
  status: paymentStatusSchema,
});

export const paymentStatusResponseSchema = z.object({
  cardId: z.string().uuid().optional(),
  test: z.boolean(),
  paymentId: z.string().uuid(),
  plan: paidPlanSchema,
  status: paymentStatusSchema,
});

export const yooKassaNotificationSchema = z.object({
  event: z.enum([
    'payment.waiting_for_capture',
    'payment.succeeded',
    'payment.canceled',
  ]),
  object: z.object({
    id: z.string().min(1),
  }),
  type: z.literal('notification'),
});

export const billingHistoryItemSchema = z.object({
  paymentId: z.string().uuid(),
  plan: paidPlanSchema,
  amountMinor: z.number().int().nonnegative(),
  currency: z.string().length(3),
  status: paymentStatusSchema,
  test: z.boolean(),
  createdAt: z.string().datetime(),
});
export type BillingHistoryItem = z.infer<typeof billingHistoryItemSchema>;

export const billingOperationSchema = z.discriminatedUnion('operation', [
  z.object({
    operation: z.literal('getPaymentHistory'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('createCheckout'),
    payload: createCheckoutSchema.extend({
      customerEmail: z.string().email(),
    }),
  }),
  z.object({
    operation: z.literal('getPaymentStatus'),
    payload: z.object({ paymentId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getCardPaymentStatus'),
    payload: z.object({ cardId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getSubscription'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('cancelSubscription'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('deleteUserData'),
    payload: z.object({ userId: z.string().uuid() }),
  }),
]);

export type Plan = z.infer<typeof planSchema>;
export type PaidPlan = z.infer<typeof paidPlanSchema>;
export type PaymentStatus = z.infer<typeof paymentStatusSchema>;
export type CreateCheckout = z.infer<typeof createCheckoutSchema>;
export type CheckoutResponse = z.infer<typeof checkoutResponseSchema>;
export type PaymentStatusResponse = z.infer<typeof paymentStatusResponseSchema>;
export type YooKassaNotification = z.infer<typeof yooKassaNotificationSchema>;
export type BillingOperation = z.infer<typeof billingOperationSchema>;

export const subscriptionCatalog = z
  .array(
    z.object({
      id: z.enum(['premium', 'super', 'ultra']),
      name: z.string(),
      amountMinor: z.number().int().positive(),
      currency: z.literal('RUB'),
    }),
  )
  .parse(catalog)
  .map(({ id, ...tier }) => ({ ...tier, plan: id }));
