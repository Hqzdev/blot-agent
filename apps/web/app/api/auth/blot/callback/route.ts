import { signIn } from '@/app/(auth)/auth';
import { blotConfiguration, callbackURL } from '@/lib/auth/blot-configuration';
import { BlotLoginFlow, attemptCookieName } from '@/lib/auth/blot-login-flow';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

export const runtime = 'nodejs';
export async function GET(request: Request) {
  const jar = await cookies();
  let stage = 'attempt';
  try {
    const configuration = blotConfiguration();
    const callback = callbackURL(request, configuration.app);
    const cookieName = attemptCookieName(callback.searchParams.get('state'));
    const saved = jar.get(cookieName)?.value;
    jar.set(cookieName, '', { path: '/app', maxAge: 0 });
    stage = saved ? 'validation' : 'missing-attempt';
    const attempt = await new BlotLoginFlow(configuration).accept(
      callback,
      saved,
    );
    stage = 'exchange';
    await signIn('blot', {
      code: attempt.code,
      codeVerifier: attempt.verifier,
      redirect: false,
      redirectTo: attempt.path,
    });
    stage = 'session';
    const sessionCookie =
      configuration.app.protocol === 'https:'
        ? '__Secure-authjs.session-token'
        : 'authjs.session-token';
    if (!jar.get(sessionCookie)?.value)
      throw new Error('Ori session unavailable');
    return NextResponse.redirect(new URL(attempt.path, configuration.app), {
      headers: {
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
      },
    });
  } catch (error) {
    console.warn('Ori browser sign-in failed', {
      stage,
      error: error instanceof Error ? error.name : 'unknown',
    });
    const origin = blotConfiguration().app;
    return NextResponse.redirect(new URL('/app/login?error=blot', origin), {
      headers: {
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
      },
    });
  }
}
