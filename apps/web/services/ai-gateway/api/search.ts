import {
  InternalRequestSigner,
  InternalRequestVerifier,
  RateLimitStoreFactory,
  RateLimiter,
} from '@teya/platform';
import {
  WebSearchController,
  WebSearchServiceFactory,
} from '@teya/service-ai-gateway';

let controller: WebSearchController | undefined;

function getController(): WebSearchController {
  if (controller) {
    return controller;
  }
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  if (!secret) {
    throw new Error('INTERNAL_SERVICE_SECRET is required');
  }
  controller = new WebSearchController(
    new InternalRequestVerifier(new InternalRequestSigner(secret)),
    new RateLimiter(
      new RateLimitStoreFactory().create(process.env),
      20,
      300,
      'ai-search',
    ),
    new WebSearchServiceFactory().create(process.env),
  );
  return controller;
}

export default function handler(request: Request): Promise<Response> {
  return getController().handle(request);
}
