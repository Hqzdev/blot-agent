import { getWebhookController } from './composition';

export default function handler(request: Request): Promise<Response> {
  return getWebhookController().handle(request);
}
