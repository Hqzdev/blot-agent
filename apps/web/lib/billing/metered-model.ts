import { wrapLanguageModel, type LanguageModelV1Middleware } from 'ai';
type LanguageModelV1 = Parameters<typeof wrapLanguageModel>[0]['model'];
import { pilot, reserveUsage, settleUsage } from './usage';

import { modelPrice } from './model-price';
export function meteredModel(
  model: LanguageModelV1,
  getOwner: () => Promise<string | undefined>,
) {
  const reserve = async (
    params: Parameters<
      NonNullable<LanguageModelV1Middleware['wrapStream']>
    >[0]['params'],
  ) => {
    const owner = await getOwner();
    if (!owner) throw new Error('Model requests require an account');
    if (!(await pilot(owner))) return;
    const estimate = modelPrice(
      Buffer.byteLength(JSON.stringify(params.prompt)),
      params.maxTokens ?? 8192,
    );
    const id = await reserveUsage(owner, estimate);
    return async (usage?: {
      promptTokens: number;
      completionTokens: number;
    }) => {
      const actual =
        usage &&
        Number.isFinite(usage.promptTokens) &&
        Number.isFinite(usage.completionTokens)
          ? modelPrice(usage.promptTokens, usage.completionTokens)
          : estimate;
      await settleUsage(owner, id, actual);
    };
  };
  return wrapLanguageModel({
    model,
    middleware: {
      transformParams: async ({ params }) => ({
        ...params,
        maxTokens: Math.min(params.maxTokens ?? 8192, 8192),
      }),
      wrapGenerate: async ({ doGenerate, params }) => {
        const settle = await reserve(params);
        let result;
        try {
          result = await doGenerate();
        } catch (error) {
          await settle?.({ promptTokens: 0, completionTokens: 0 });
          throw error;
        }
        await settle?.(result.usage);
        return result;
      },
      wrapStream: async ({ doStream, params }) => {
        const settle = await reserve(params);
        let result;
        try {
          result = await doStream();
        } catch (error) {
          await settle?.({ promptTokens: 0, completionTokens: 0 });
          throw error;
        }
        if (!settle) return result;
        const reader = result.stream.getReader();
        return {
          ...result,
          stream: new ReadableStream({
            async pull(controller) {
              try {
                const { done, value } = await reader.read();
                if (done) {
                  await settle();
                  controller.close();
                  return;
                }
                if (value.type === 'finish') await settle(value.usage);
                controller.enqueue(value);
              } catch (error) {
                await settle();
                controller.error(error);
              }
            },
            async cancel(reason) {
              try {
                await reader.cancel(reason);
              } finally {
                await settle();
              }
            },
          }),
        };
      },
    },
  });
}
