import 'server-only';

import {
  BillingService,
  BillingWebhookController,
  PaymentProviderFactory,
  PostgresBillingRepository,
} from '@teya/service-billing';

let controller: BillingWebhookController | undefined;

export function getBillingWebhookController(): BillingWebhookController {
  if (!controller) {
    controller = new BillingWebhookController(
      new BillingService(
        new PostgresBillingRepository(),
        new PaymentProviderFactory().create(process.env),
      ),
    );
  }
  return controller;
}
