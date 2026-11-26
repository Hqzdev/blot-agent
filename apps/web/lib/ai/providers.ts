import { meteredModel } from '@/lib/billing/metered-model';
import { TeyaModelProviderFactory } from '@teya/service-ai-gateway';
import { customProvider } from 'ai';

import { isTestEnvironment } from '../constants';
import {
  artifactModel,
  chatModel,
  reasoningModel,
  titleModel,
} from './models.test';

const testProvider = customProvider({
  languageModels: {
    'artifact-model': artifactModel,
    'chat-model': chatModel,
    'chat-model-reasoning': reasoningModel,
    'title-model': titleModel,
  },
});

const provider = isTestEnvironment
  ? testProvider
  : new TeyaModelProviderFactory().create(process.env);

export const myProvider = {
  languageModel(id: Parameters<typeof provider.languageModel>[0]) {
    const model = provider.languageModel(id);
    if (isTestEnvironment) return model;
    return meteredModel(
      model,
      async () => (await (await import('@/app/(auth)/auth')).auth())?.user?.id,
    );
  },
};
