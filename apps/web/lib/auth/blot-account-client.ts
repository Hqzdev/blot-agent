import { z } from 'zod';
import { blotConfiguration } from './blot-configuration';

const tokenSchema = z.object({
  accessToken: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  ownerID: z.string().uuid(),
  expiresAt: z.string().datetime(),
});
export const accountSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string(),
  verified: z.literal(true),
  avatarURL: z.string().url().nullable().optional(),
});
export type BlotAccount = z.infer<typeof accountSchema>;

export class BlotAccountError extends Error {
  constructor(readonly status: number) {
    super('Blot account request failed');
  }
}

export class BlotAccountClient {
  constructor(
    private readonly configuration = blotConfiguration(),
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async exchange(code: string, verifier: string) {
    const tokens = tokenSchema.parse(
      await this.request('browser/token', {
        code,
        codeVerifier: verifier,
        clientID: 'blot-web',
        redirectURI: this.configuration.redirectURI,
      }),
    );
    if (Date.parse(tokens.expiresAt) <= Date.now() + 30_000)
      throw new BlotAccountError(401);
    const account = await this.profile(tokens.accessToken);
    if (account.id !== tokens.ownerID) throw new BlotAccountError(401);
    return { tokens, account };
  }

  async profile(accessToken: string) {
    return accountSchema.parse(
      await this.request('me', undefined, accessToken),
    );
  }
  async logout(accessToken: string) {
    await this.request('logout', {}, accessToken);
  }

  async request(
    path: string,
    body?: unknown,
    accessToken?: string,
  ): Promise<unknown> {
    const response = await this.fetcher(
      new URL(`/v1/auth/${path}`, this.configuration.account),
      {
        method: body === undefined ? 'GET' : 'POST',
        redirect: 'error',
        cache: 'no-store',
        signal: AbortSignal.timeout(15_000),
        headers: {
          Accept: 'application/json',
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
          ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      },
    );
    if (!response.ok) {
      await response.body?.cancel();
      throw new BlotAccountError(response.status);
    }
    const reader = response.body?.getReader();
    if (!reader) return null;
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const result = await reader.read();
        if (result.done) break;
        size += result.value.length;
        if (size > 65_536) throw new BlotAccountError(502);
        chunks.push(result.value);
      }
    } finally {
      await reader.cancel();
    }
    return size ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : null;
  }
}
