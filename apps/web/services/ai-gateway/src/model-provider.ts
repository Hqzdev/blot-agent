import { createOpenAI } from '@ai-sdk/openai';
import {
  customProvider,
  extractReasoningMiddleware,
  wrapLanguageModel,
} from 'ai';

import {
  GigaChatAccessTokenProvider,
  GigaChatAuthenticatedClient,
  TrustedHttpsClient,
} from './gigachat';
import { GIGACHAT_REASONING_TAG } from './gigachat-reasoning';
import { russianTrustedRootCertificate } from './russian-trusted-root-ca';

export class TeyaModelProviderFactory {
  create(environment: NodeJS.ProcessEnv) {
    const internalSecret = environment.INTERNAL_SERVICE_SECRET;
    const gatewayUrl = environment.AI_GATEWAY_URL;
    const useGateway = Boolean(gatewayUrl);
    const gigaChatModel =
      environment.GIGACHAT_MODEL?.trim() ||
      environment.BLOT_GIGACHAT_MODEL?.trim() ||
      'GigaChat-3-Ultra';
    const gigaChatScope =
      environment.GIGACHAT_SCOPE?.trim() ||
      environment.BLOT_GIGACHAT_SCOPE?.trim() ||
      'GIGACHAT_API_PERS';

    if (useGateway && !internalSecret) {
      throw new Error('INTERNAL_SERVICE_SECRET is required');
    }

    const provider = useGateway
      ? createOpenAI({
          apiKey: internalSecret,
          baseURL: `${gatewayUrl?.replace(/\/$/, '')}/api`,
        })
      : this.createDirectProvider(
          environment.GIGACHAT_AUTH_KEY ??
            environment.BLOT_GIGACHAT_AUTH_KEY ??
            '',
          gigaChatScope,
        );
    const model = useGateway ? 'teya' : gigaChatModel;
    const modelSettings = {
      parallelToolCalls: false,
      useLegacyFunctionCalling: true,
    };
    const languageModel = provider(model, modelSettings);
    const reasoningModel = wrapLanguageModel({
      model: provider(model, {
        ...modelSettings,
        reasoningEffort: 'medium',
      }),
      middleware: extractReasoningMiddleware({
        tagName: GIGACHAT_REASONING_TAG,
        startWithReasoning: true,
      }),
    });
    return customProvider({
      imageModels: {},
      languageModels: {
        'artifact-model': languageModel,
        'chat-model': languageModel,
        'chat-model-reasoning': reasoningModel,
        'title-model': languageModel,
      },
    });
  }

  private createDirectProvider(authorizationKey: string, scope: string) {
    const httpsClient = new TrustedHttpsClient({
      certificate: russianTrustedRootCertificate,
    });
    const fetcher = (input: RequestInfo | URL, init?: RequestInit) =>
      httpsClient.request(input, init);
    const tokenProvider = new GigaChatAccessTokenProvider({
      authorizationKey,
      fetcher,
      scope,
    });
    const authenticatedClient = new GigaChatAuthenticatedClient({
      fetcher,
      tokenProvider,
    });
    return createOpenAI({
      apiKey: 'managed-by-gigachat-auth',
      baseURL: 'https://api.giga.chat/v1',
      fetch: (input, init) => authenticatedClient.request(input, init),
    });
  }
}
