import { Buffer } from 'node:buffer';

import { z } from 'zod';

import {
  GigaChatAccessTokenProvider,
  GigaChatAuthenticatedClient,
  GigaChatCompletionClient,
  TrustedHttpsClient,
} from './gigachat';
import { russianTrustedRootCertificate } from './russian-trusted-root-ca';

const imageCompletionSchema = z.object({
  choices: z
    .array(
      z.object({
        message: z.object({
          content: z.string(),
        }),
      }),
    )
    .min(1),
});

export type GeneratedImage = {
  base64: string;
  contentType: string;
};

export class GigaChatImageGenerator {
  private readonly baseUrl: string;
  private readonly client: GigaChatAuthenticatedClient;
  private readonly completionClient: GigaChatCompletionClient;

  constructor(options: {
    baseUrl?: string;
    client: GigaChatAuthenticatedClient;
    model: string;
  }) {
    this.baseUrl = (options.baseUrl ?? 'https://api.giga.chat/v1').replace(
      /\/$/,
      '',
    );
    this.client = options.client;
    this.completionClient = new GigaChatCompletionClient({
      baseUrl: this.baseUrl,
      client: options.client,
      model: options.model,
    });
  }

  async generate(
    prompt: string,
    signal = AbortSignal.timeout(240_000),
  ): Promise<GeneratedImage> {
    const completionResponse = await this.completionClient.complete(
      {
        function_call: 'auto',
        messages: [
          {
            content:
              'Ты — профессиональный художник. Создавай изображение по описанию пользователя.',
            role: 'system',
          },
          {
            content: `Нарисуй изображение: ${prompt}`,
            role: 'user',
          },
        ],
        stream: false,
      },
      signal,
    );
    if (!completionResponse.ok) {
      throw new Error(
        `GigaChat image generation failed with ${completionResponse.status}`,
      );
    }

    const completion = imageCompletionSchema.parse(
      await completionResponse.json(),
    );
    const fileId = this.extractFileId(completion.choices[0].message.content);
    const imageResponse = await this.client.request(
      `${this.baseUrl}/files/${fileId}/content`,
      {
        headers: { accept: 'image/jpeg' },
        method: 'GET',
        signal,
      },
    );
    if (!imageResponse.ok) {
      throw new Error(
        `GigaChat image download failed with ${imageResponse.status}`,
      );
    }

    return {
      base64: Buffer.from(await imageResponse.arrayBuffer()).toString('base64'),
      contentType:
        imageResponse.headers.get('content-type')?.split(';')[0] ||
        'image/jpeg',
    };
  }

  private extractFileId(content: string): string {
    const match = content.match(
      /<img\b[^>]*\bsrc=["']([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})["']/i,
    );
    const parsed = z.string().uuid().safeParse(match?.[1]);
    if (!parsed.success) {
      throw new Error('GigaChat did not return a generated image');
    }
    return parsed.data;
  }
}

export class GigaChatImageGeneratorFactory {
  create(environment: NodeJS.ProcessEnv): GigaChatImageGenerator {
    const authorizationKey = environment.GIGACHAT_AUTH_KEY?.trim() ?? '';
    if (!authorizationKey) {
      throw new Error('GIGACHAT_AUTH_KEY is required for image generation');
    }
    const trustedClient = new TrustedHttpsClient({
      certificate: russianTrustedRootCertificate,
    });
    const fetcher = (input: RequestInfo | URL, init?: RequestInit) =>
      trustedClient.request(input, init);
    const tokenProvider = new GigaChatAccessTokenProvider({
      authorizationKey,
      fetcher,
      scope: environment.GIGACHAT_SCOPE?.trim() || 'GIGACHAT_API_PERS',
    });
    const client = new GigaChatAuthenticatedClient({
      fetcher,
      tokenProvider,
    });
    return new GigaChatImageGenerator({
      client,
      model: environment.GIGACHAT_MODEL?.trim() || 'GigaChat',
    });
  }
}
