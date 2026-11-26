import { blotConfiguration, trustedProxy } from '@/lib/auth/blot-configuration';
import { BlotLoginFlow } from '@/lib/auth/blot-login-flow';
import { NextResponse } from 'next/server';

export const runtime = 'nodejs';
export async function GET(request: Request) {
  try {
    const configuration = blotConfiguration();
    const incoming = new URL(request.url);
    const host =
      request.headers.get('x-forwarded-host') ||
      request.headers.get('host') ||
      incoming.host;
    if (!trustedProxy(request) && host !== configuration.app.host) {
      const canonical = new URL('/app/api/auth/blot/start', configuration.app);
      canonical.search = incoming.search;
      return NextResponse.redirect(canonical);
    }
    const query = new URL(request.url).searchParams;
    const attempt = await new BlotLoginFlow(configuration).start(
      query.get('callbackUrl'),
      query.get('intent') === 'register',
    );
    const response = NextResponse.redirect(attempt.url);
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.cookies.set(attempt.cookieName, attempt.cookie, {
      httpOnly: true,
      sameSite: 'lax',
      secure: configuration.app.protocol === 'https:',
      maxAge: 300,
      path: '/app',
    });
    return response;
  } catch {
    return NextResponse.json(
      {
        error:
          'Вход Ori не настроен. Проверьте BLOT_AUTH_URL, AUTH_URL и AUTH_SECRET.',
      },
      { status: 503 },
    );
  }
}
