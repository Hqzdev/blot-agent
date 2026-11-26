import { createWebRateLimitStore } from '@/lib/services/web-rate-limit-store';
import { webSearchRequestSchema } from '@teya/contracts';
import { RateLimiter } from '@teya/platform';
import { NextResponse } from 'next/server';
import { ZodError } from 'zod';

import { auth } from '@/app/(auth)/auth';
import { getAiSearchGateway } from '@/lib/services/ai-search-gateway';

let rateLimiter: RateLimiter | undefined;

function getRateLimiter(): RateLimiter {
  if (!rateLimiter) {
    rateLimiter = new RateLimiter(
      createWebRateLimitStore(),
      20,
      300,
      'web-search',
    );
  }
  return rateLimiter;
}

export async function POST(request: Request) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const decision = await getRateLimiter().consume(userId);
    if (!decision.allowed) {
      return NextResponse.json(
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
    const input = webSearchRequestSchema.parse(await request.json());
    const response = await getAiSearchGateway().search(userId, input.query);
    return NextResponse.json(response, {
      headers: {
        'cache-control': 'private, max-age=60',
      },
    });
  } catch (error) {
    if (error instanceof ZodError || error instanceof SyntaxError) {
      return NextResponse.json(
        { error: 'Invalid search query' },
        { status: 400 },
      );
    }
    return NextResponse.json(
      { error: 'Search is temporarily unavailable' },
      { status: 502 },
    );
  }
}
