import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  BillingRpcController,
  BillingService,
  BillingWebhookController,
  PaymentProviderFactory,
  PostgresBillingRepository,
} from '@teya/service-billing';

let billingService: BillingService | undefined;
let rpcController: BillingRpcController | undefined;
let webhookController: BillingWebhookController | undefined;

function getService(): BillingService {
  if (!billingService) {
    billingService = new BillingService(
      new PostgresBillingRepository(),
      new PaymentProviderFactory().create(process.env),
    );
  }
  return billingService;
}

export function getRpcController(): BillingRpcController {
  if (rpcController) {
    return rpcController;
  }
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  if (!secret) {
    throw new Error('INTERNAL_SERVICE_SECRET is required');
  }
  rpcController = new BillingRpcController(
    new InternalRequestVerifier(new InternalRequestSigner(secret)),
    getService(),
  );
  return rpcController;
}

export function getWebhookController(): BillingWebhookController {
  if (!webhookController) {
    webhookController = new BillingWebhookController(getService());
  }
  return webhookController;
}
