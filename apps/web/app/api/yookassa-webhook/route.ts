import { getBillingWebhookController } from '@/lib/services/billing-webhook';

export async function POST(request: Request): Promise<Response> {
  const serviceUrl = process.env.BILLING_SERVICE_URL;
  if (!serviceUrl) {
    return getBillingWebhookController().handle(request);
  }

  const body = await request.text();
  const response = await fetch(new URL('/api/webhook', serviceUrl), {
    body,
    headers: {
      'content-type': 'application/json',
    },
    method: 'POST',
  });
  return new Response(response.body, {
    headers: {
      'content-type':
        response.headers.get('content-type') ?? 'application/json',
    },
    status: response.status,
  });
}
