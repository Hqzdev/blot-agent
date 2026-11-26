import {
  GigaChatAccessTokenProvider,
  GigaChatAuthenticatedClient,
  GigaChatCompletionClient,
  ModelProxyController,
  TrustedHttpsClient,
  russianTrustedRootCertificate,
} from '@teya/service-ai-gateway';

let controller: ModelProxyController | undefined;

function getController(): ModelProxyController {
  if (controller) {
    return controller;
  }
  const internalSecret = process.env.INTERNAL_SERVICE_SECRET;
  const authorizationKey = process.env.GIGACHAT_AUTH_KEY;
  if (!internalSecret || !authorizationKey) {
    throw new Error(
      'INTERNAL_SERVICE_SECRET and GIGACHAT_AUTH_KEY are required',
    );
  }
  const httpsClient = new TrustedHttpsClient({
    certificate: russianTrustedRootCertificate,
  });
  const fetcher = (input: RequestInfo | URL, init?: RequestInit) =>
    httpsClient.request(input, init);
  const tokenProvider = new GigaChatAccessTokenProvider({
    authorizationKey,
    fetcher,
    scope: process.env.GIGACHAT_SCOPE || 'GIGACHAT_API_PERS',
  });
  const authenticatedClient = new GigaChatAuthenticatedClient({
    fetcher,
    tokenProvider,
  });
  const completionClient = new GigaChatCompletionClient({
    client: authenticatedClient,
    model: process.env.GIGACHAT_MODEL || 'GigaChat-3-Ultra',
  });
  controller = new ModelProxyController(internalSecret, completionClient);
  return controller;
}

export default function handler(request: Request): Promise<Response> {
  return getController().handle(request);
}
