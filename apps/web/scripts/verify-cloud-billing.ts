import 'dotenv/config';
import { subscriptionCatalog } from '@teya/contracts';
import { DatabaseConnectionProvider } from '@teya/database';
import {
  PaymentProviderFactory,
  PostgresBillingRepository,
} from '@teya/service-billing';

const provider = new PaymentProviderFactory().create(process.env);
await provider.verifyTestShop();
const database = new DatabaseConnectionProvider().get();
try {
  const repository = new PostgresBillingRepository();
  for (const tier of subscriptionCatalog) {
    const plan = await repository.getPlan(tier.plan);
    if (
      !plan ||
      plan.amountMinor !== tier.amountMinor ||
      plan.currency !== tier.currency
    ) {
      throw new Error(`Billing catalog migration is missing for ${tier.plan}`);
    }
  }
  console.log(
    'Blot billing ready: verified test shop and three RUB plans; no payment created.',
  );
} finally {
  await database.close();
}
