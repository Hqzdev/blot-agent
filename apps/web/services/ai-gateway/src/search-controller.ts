import { webSearchRequestSchema } from '@teya/contracts';
import { InternalRequestVerifier, type RateLimiter } from '@teya/platform';
import { ZodError } from 'zod';

import type { WebSearchService } from './search';

export class WebSearchController {
  constructor(
    private readonly verifier: InternalRequestVerifier,
    private readonly rateLimiter: RateLimiter,
    private readonly service: WebSearchService,
  ) {}

  async handle(request: Request): Promise<Response> {
    const body = await request.text();
    try {
      const identity = this.verifier.verify(request, body);
      if (identity.actorId.startsWith('system:')) {
        return Response.json({ error: 'User actor required' }, { status: 403 });
      }
      const decision = await this.rateLimiter.consume(identity.actorId);
      if (!decision.allowed) {
        return Response.json(
          { error: 'Rate limit exceeded' },
          {
            headers: {
              'retry-after': Math.max(
                1,
                Math.ceil((decision.resetAt.getTime() - Date.now()) / 1000),
              ).toString(),
            },
            status: 429,
          },
        );
      }
      const input = webSearchRequestSchema.parse(JSON.parse(body));
      const result = await this.service.search(input.query);
      return Response.json(result);
    } catch (error) {
      if (error instanceof SyntaxError || error instanceof ZodError) {
        return Response.json({ error: 'Invalid request' }, { status: 400 });
      }
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }
}
