import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { decode, encode } from 'next-auth/jwt';
import { z } from 'zod';
import { blotConfiguration, returnPath } from './blot-configuration';

export const attemptCookie = 'blot_login_attempt';
export function attemptCookieName(state: string | null): string {
  if (!state || !/^[A-Za-z0-9_-]{43}$/.test(state))
    throw new Error('Invalid login state');
  return `${attemptCookie}_${state}`;
}
const attemptSchema = z.object({
  state: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  verifier: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  path: z.string(),
  redirectURI: z.string(),
});

export class BlotLoginFlow {
  constructor(private readonly configuration = blotConfiguration()) {}

  async start(path: unknown, registering: boolean) {
    const state = randomBytes(32).toString('base64url');
    const verifier = randomBytes(32).toString('base64url');
    const cookie = await encode({
      secret: this.configuration.secret,
      salt: attemptCookie,
      maxAge: 300,
      token: {
        state,
        verifier,
        path: returnPath(path),
        redirectURI: this.configuration.redirectURI,
      },
    });
    const url = new URL(this.configuration.login);
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: 'blot-web',
      redirect_uri: this.configuration.redirectURI,
      state,
      code_challenge: createHash('sha256').update(verifier).digest('base64url'),
      code_challenge_method: 'S256',
      intent: registering ? 'register' : 'login',
    }).toString();
    return { url, cookie, cookieName: attemptCookieName(state) };
  }

  async accept(callback: URL, cookie: string | undefined) {
    if (!cookie) throw new Error('Missing login attempt');
    const saved = attemptSchema.parse(
      await decode({
        token: cookie,
        secret: this.configuration.secret,
        salt: attemptCookie,
      }),
    );
    const expected = new URL(this.configuration.redirectURI);
    const state = callback.searchParams.get('state') || '';
    const code = callback.searchParams.get('code') || '';
    if (
      callback.origin !== expected.origin ||
      callback.pathname !== expected.pathname ||
      callback.hash ||
      callback.searchParams.getAll('state').length !== 1 ||
      callback.searchParams.getAll('code').length !== 1 ||
      [...callback.searchParams.keys()].some(
        (key) => !['state', 'code'].includes(key),
      ) ||
      saved.redirectURI !== expected.href ||
      state.length !== saved.state.length ||
      !timingSafeEqual(Buffer.from(state), Buffer.from(saved.state)) ||
      !/^[A-Za-z0-9_-]{43}$/.test(code)
    ) {
      throw new Error('Invalid login callback');
    }
    return { code, verifier: saved.verifier, path: returnPath(saved.path) };
  }
}
