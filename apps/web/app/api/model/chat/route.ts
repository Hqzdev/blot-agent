import { z } from 'zod';
import { RateLimiter } from '@teya/platform';
import {
  GigaChatAccessTokenProvider,
  GigaChatAuthenticatedClient,
  GigaChatCompletionClient,
  TrustedHttpsClient,
  russianTrustedRootCertificate,
} from '@teya/service-ai-gateway';
import { billingOwner } from '@/lib/services/billing-identity';
import { createWebRateLimitStore } from '@/lib/services/web-rate-limit-store';
import {
  pilot,
  QuotaExceeded,
  reserveUsage,
  settleUsage,
} from '@/lib/billing/usage';
import { modelPrice } from '@/lib/billing/model-price';

const completion = z.object({
  messages: z
    .array(
      z
        .object({
          role: z.enum(['system', 'user', 'assistant', 'function']),
          content: z.string(),
        })
        .passthrough(),
    )
    .min(1)
    .max(200),
  functions: z
    .array(z.object({ name: z.string() }).passthrough())
    .max(256)
    .optional(),
  function_call: z
    .union([z.literal('auto'), z.object({ name: z.string() })])
    .optional(),
  max_tokens: z.number().int().positive().max(32768),
  stream: z.literal(true),
});
const schema = z.union([
  z.object({ tier: z.enum(['mini', 'pro', 'max']), completion }).strict(),
  completion.transform((legacy) => ({ tier: undefined, completion: legacy })),
]);
let client: GigaChatCompletionClient | undefined;
function provider() {
  if (client) return client;
  const authorizationKey =
    process.env.BLOT_GIGACHAT_AUTH_KEY ?? process.env.GIGACHAT_AUTH_KEY;
  if (!authorizationKey) throw new Error('Managed model unavailable');
  const transport = new TrustedHttpsClient({
    certificate: russianTrustedRootCertificate,
  });
  const fetcher = (input: RequestInfo | URL, init?: RequestInit) =>
    transport.request(input, init);
  const tokenProvider = new GigaChatAccessTokenProvider({
    authorizationKey,
    fetcher,
    scope: process.env.BLOT_GIGACHAT_SCOPE ?? 'GIGACHAT_API_PERS',
  });
  client = new GigaChatCompletionClient({
    client: new GigaChatAuthenticatedClient({ fetcher, tokenProvider }),
    model: process.env.BLOT_GIGACHAT_MODEL ?? 'GigaChat-3-Ultra',
  });
  return client;
}
export async function POST(request: Request) {
  if (!request.headers.has('authorization'))
    return new Response(null, { status: 401 });
  const owner = await billingOwner(request);
  if (!owner) return new Response(null, { status: 401 });
  const rate = await new RateLimiter(
    createWebRateLimitStore(),
    80,
    10800,
    'chat',
  ).consume(owner);
  if (!rate.allowed) return new Response(null, { status: 429 });
  const raw = await request.text();
  if (Buffer.byteLength(raw) > 2000000)
    return new Response(null, { status: 413 });
  const input = schema.safeParse(
    await Promise.resolve()
      .then(() => JSON.parse(raw))
      .catch(() => null),
  );
  if (!input.success) return new Response(null, { status: 400 });
  let id: string | undefined;
  const enabled = await pilot(owner);
  const estimate = enabled
    ? modelPrice(Buffer.byteLength(raw), input.data.completion.max_tokens)
    : 0;
  try {
    if (enabled) id = await reserveUsage(owner, estimate);
  } catch (error) {
    if (error instanceof QuotaExceeded)
      return Response.json(
        { error: 'quota_exceeded', resetsAt: error.resetsAt },
        {
          status: 429,
          headers: { 'x-blot-quota-reset': error.resetsAt.toISOString() },
        },
      );
    throw error;
  }
  let response;
  try {
    response = await provider().complete(input.data.completion, request.signal, input.data.tier);
  } catch (error) {
    if (id) await settleUsage(owner, id, estimate);
    throw error;
  }
  if (!response.ok || !response.body) {
    if (id) await settleUsage(owner, id, 0);
    return new Response(null, { status: 502 });
  }
  const headers = {
    'content-type': 'text/event-stream',
    'cache-control': 'no-store',
  };
  if (!id) return new Response(response.body, { headers });
  const reservation = id;
  const reader = response.body.getReader(),
    decoder = new TextDecoder();
  let pending = '',
    actual = estimate;
  return new Response(
    new ReadableStream({
      async pull(controller) {
        try {
          const { done, value } = await reader.read();
          if (done) {
            await settleUsage(owner, reservation, actual);
            controller.close();
            return;
          }
          pending += decoder.decode(value, { stream: true });
          const lines = pending.split('\n');
          pending = lines.pop() ?? '';
          if (pending.length > 2000000)
            throw new Error('Invalid provider stream');
          for (const line of lines) {
            if (!line.startsWith('data:') || line.slice(5).trim() === '[DONE]')
              continue;
            const usage = JSON.parse(line.slice(5)).usage;
            if (
              usage &&
              [usage.prompt_tokens, usage.completion_tokens].every(
                (n) => Number.isSafeInteger(n) && n >= 0,
              )
            )
              actual = modelPrice(usage.prompt_tokens, usage.completion_tokens);
          }
          controller.enqueue(value);
        } catch (error) {
          await reader.cancel();
          await settleUsage(owner, reservation, actual);
          controller.error(error);
        }
      },
      async cancel(reason) {
        try {
          await reader.cancel(reason);
        } finally {
          await settleUsage(owner, reservation, actual);
        }
      },
    }),
    { headers },
  );
}
