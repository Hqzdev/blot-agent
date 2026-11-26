import {
  type BillingOperation,
  billingOperationSchema,
  yooKassaNotificationSchema,
} from '@teya/contracts';
import { InternalRequestVerifier } from '@teya/platform';
import { ZodError } from 'zod';

import {
  BillingConflictError,
  BillingForbiddenError,
  BillingNotFoundError,
  BillingProviderError,
  BillingValidationError,
} from './errors';
import type { BillingService } from './service';

export class BillingRpcController {
  constructor(
    private readonly verifier: InternalRequestVerifier,
    private readonly service: BillingService,
  ) {}

  async handle(request: Request): Promise<Response> {
    const body = await request.text();
    try {
      const identity = this.verifier.verify(request, body);
      const operation = billingOperationSchema.parse(JSON.parse(body));
      const result = await this.execute(identity.actorId, operation);
      return Response.json({ result });
    } catch (error) {
      return this.toErrorResponse(error);
    }
  }

  private execute(actorId: string, operation: BillingOperation) {
    if (operation.operation === 'deleteUserData') {
      if (actorId !== 'system:web') {
        throw new BillingForbiddenError('Operation requires the web service');
      }
      return this.service.deleteUserData(operation.payload.userId);
    }
    if (actorId.startsWith('system:')) {
      throw new BillingForbiddenError('Operation requires a user actor');
    }

    switch (operation.operation) {
      case 'getPaymentHistory':
        return this.service.getPaymentHistory(actorId);
      case 'createCheckout':
        return this.service.createCheckout({
          ...operation.payload,
          userId: actorId,
        });
      case 'getPaymentStatus':
        return this.service.getPaymentStatus(
          actorId,
          operation.payload.paymentId,
        );
      case 'getCardPaymentStatus':
        return this.service.getCardPaymentStatus(
          actorId,
          operation.payload.cardId,
        );
      case 'getSubscription':
        return this.service.getSubscription(actorId);
      case 'cancelSubscription':
        return this.service.cancelSubscription(actorId);
    }
  }

  private toErrorResponse(error: unknown): Response {
    if (error instanceof SyntaxError || error instanceof ZodError) {
      return Response.json({ error: 'Invalid request' }, { status: 400 });
    }
    if (error instanceof BillingConflictError) {
      return Response.json({ error: error.message }, { status: 409 });
    }
    if (error instanceof BillingNotFoundError) {
      return Response.json({ error: error.message }, { status: 404 });
    }
    if (error instanceof BillingForbiddenError) {
      return Response.json({ error: error.message }, { status: 403 });
    }
    if (
      error instanceof BillingProviderError ||
      error instanceof BillingValidationError
    ) {
      return Response.json({ error: error.message }, { status: 422 });
    }
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
}

export class BillingWebhookController {
  constructor(private readonly service: BillingService) {}

  async handle(request: Request): Promise<Response> {
    try {
      const notification = yooKassaNotificationSchema.parse(
        await request.json(),
      );
      await this.service.processNotification(notification);
      return Response.json({ received: true });
    } catch (error) {
      if (error instanceof ZodError || error instanceof SyntaxError) {
        return Response.json(
          { error: 'Invalid notification' },
          { status: 400 },
        );
      }
      if (error instanceof BillingNotFoundError) {
        return Response.json({ error: error.message }, { status: 404 });
      }
      if (
        error instanceof BillingProviderError ||
        error instanceof BillingValidationError
      ) {
        return Response.json({ error: error.message }, { status: 422 });
      }
      return Response.json(
        { error: 'Webhook processing failed' },
        { status: 500 },
      );
    }
  }
}
