import 'server-only';

import type { WebSearchResponse } from '@teya/contracts';
import { InternalApiClient } from '@teya/platform';
import { WebSearchServiceFactory } from '@teya/service-ai-gateway';

export interface AiSearchGateway {
  search(userId: string, query: string): Promise<WebSearchResponse>;
}

class LocalAiSearchGateway implements AiSearchGateway {
  private readonly service = new WebSearchServiceFactory().create(process.env);

  search(_userId: string, query: string): Promise<WebSearchResponse> {
    return this.service.search(query);
  }
}

class HttpAiSearchGateway implements AiSearchGateway {
  private readonly client: InternalApiClient;

  constructor(baseUrl: string, secret: string) {
    this.client = new InternalApiClient(baseUrl, secret);
  }

  search(userId: string, query: string): Promise<WebSearchResponse> {
    return this.client.request<WebSearchResponse>({
      actorId: userId,
      body: { query },
      path: '/api/search',
    });
  }
}

let aiSearchGateway: AiSearchGateway | undefined;

export function getAiSearchGateway(): AiSearchGateway {
  if (aiSearchGateway) {
    return aiSearchGateway;
  }
  const serviceUrl = process.env.AI_GATEWAY_URL;
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  aiSearchGateway =
    serviceUrl && secret
      ? new HttpAiSearchGateway(serviceUrl, secret)
      : new LocalAiSearchGateway();
  return aiSearchGateway;
}
