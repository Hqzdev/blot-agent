import { handlers } from '@/app/(auth)/auth';
import { webPath } from '@/lib/web-path';
import { NextRequest } from 'next/server';

// Next.js strips its basePath from route requests; Auth.js expects the public path.
function publicRequest(request: NextRequest) {
  const url = new URL(request.url);
  url.pathname = webPath(url.pathname);
  return new NextRequest(url, request);
}

export const GET = (request: NextRequest) =>
  handlers.GET(publicRequest(request));
export const POST = (request: NextRequest) =>
  handlers.POST(publicRequest(request));
