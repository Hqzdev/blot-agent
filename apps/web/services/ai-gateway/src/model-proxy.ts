import { timingSafeEqual } from 'node:crypto';

import { z } from 'zod';

const modelRequestSchema = z
  .object({
    max_tokens: z.number().int().positive().max(32_768).optional(),
    messages: z.array(z.unknown()).min(1).max(200),
    model: z.string(),
    stream: z.boolean().optional(),
  })
  .passthrough();

export interface ModelCompletionClient {
  complete(
    payload: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<Response>;
}

export class ModelProxyController {
  constructor(
    private readonly internalSecret: string,
    private readonly completionClient: ModelCompletionClient,
  ) {}

  async handle(request: Request): Promise<Response> {
    if (!this.isAuthorized(request)) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
    const body = await request.text();
    if (body.length > 2_000_000) {
      return Response.json({ error: 'Request is too large' }, { status: 413 });
    }

    let payload: z.infer<typeof modelRequestSchema>;
    try {
      payload = modelRequestSchema.parse(JSON.parse(body));
    } catch {
      return Response.json({ error: 'Invalid request' }, { status: 400 });
    }

    const response = await this.completionClient.complete(
      {
        ...payload,
        max_tokens: Math.min(payload.max_tokens ?? 8192, 32_768),
      },
      request.signal,
    );

    return new Response(response.body, {
      headers: {
        'cache-control': 'no-store',
        'content-type':
          response.headers.get('content-type') ?? 'application/json',
      },
      status: response.status,
    });
  }

  private isAuthorized(request: Request): boolean {
    const authorization = request.headers.get('authorization');
    if (!authorization?.startsWith('Bearer ')) {
      return false;
    }
    const supplied = Buffer.from(authorization.slice(7));
    const expected = Buffer.from(this.internalSecret);
    return (
      supplied.length === expected.length && timingSafeEqual(supplied, expected)
    );
  }
}
