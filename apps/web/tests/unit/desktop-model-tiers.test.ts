import assert from 'node:assert/strict';
import test from 'node:test';

import {
  GigaChatAuthenticatedClient,
  GigaChatCompletionClient,
} from '@teya/service-ai-gateway';

test('desktop tiers reach distinct upstream models and legacy callers retain the configured model', async () => {
  const models: string[] = [];
  const client = new GigaChatCompletionClient({
    model: 'legacy',
    client: new GigaChatAuthenticatedClient({
      tokenProvider: { getAccessToken: async () => 'test', invalidate() {} },
      fetcher: async (_, init) => {
        models.push(JSON.parse(String(init?.body)).model);
        return Response.json({});
      },
    }),
  });
  for (const tier of [undefined, 'mini', 'pro', 'max'] as const) {
    await client.complete({ model: 'ignored' }, new AbortController().signal, tier);
  }
  assert.deepEqual(models, ['legacy', 'GigaChat-2', 'GigaChat-2-Pro', 'GigaChat-2-Max']);
});
