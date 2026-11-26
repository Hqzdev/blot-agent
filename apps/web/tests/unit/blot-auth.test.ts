import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import {
  BlotAccountClient,
  BlotAccountError,
} from '../../lib/auth/blot-account-client';
import {
  blotConfiguration,
  callbackURL,
  returnPath,
} from '../../lib/auth/blot-configuration';
import { BlotLoginFlow } from '../../lib/auth/blot-login-flow';

const configuration = blotConfiguration({
  NODE_ENV: 'test',
  AUTH_SECRET: 's'.repeat(48),
  AUTH_URL: 'https://web.blot.example',
  BLOT_AUTH_URL: 'https://blot.example/login',
  BLOT_ACCOUNT_SERVICE_URL: 'https://blot.example',
});

test('Ori login binds browser state, encrypted verifier and exact callback', async () => {
  const flow = new BlotLoginFlow(configuration);
  const first = await flow.start('/projects?filter=mine', false);
  const second = await flow.start('/chat', true);
  assert.equal(first.url.origin, 'https://blot.example');
  assert.equal(first.url.searchParams.get('client_id'), 'blot-web');
  assert.equal(second.url.searchParams.get('intent'), 'register');
  assert.notEqual(
    first.url.searchParams.get('state'),
    second.url.searchParams.get('state'),
  );
  assert.notEqual(first.cookieName, second.cookieName);
  assert.equal(first.url.searchParams.has('code_verifier'), false);
  const callback = new URL(configuration.redirectURI);
  callback.search = new URLSearchParams({
    code: 'c'.repeat(43),
    state: first.url.searchParams.get('state') || '',
  }).toString();
  const accepted = await flow.accept(callback, first.cookie);
  assert.equal(accepted.path, '/app/projects?filter=mine');
  assert.equal(first.cookie.includes(accepted.verifier), false);
  await assert.rejects(flow.accept(callback, second.cookie));
  await assert.rejects(
    flow.accept(callback, `${first.cookie.slice(0, -8)}tampered`),
  );
  await assert.rejects(flow.accept(callback, undefined));
  for (const mutation of [
    (url: URL) => url.searchParams.append('state', 'duplicate'),
    (url: URL) => url.searchParams.set('access_token', 'untrusted'),
    (url: URL) => {
      url.hostname = 'other.example';
    },
    (url: URL) => url.searchParams.set('code', 'short'),
  ]) {
    const changed = new URL(callback);
    mutation(changed);
    await assert.rejects(flow.accept(changed, first.cookie));
  }
});

test('Ori configuration and return paths reject credentials and redirect injection', () => {
  for (const path of [
    '//evil.example',
    '/\\evil.example',
    '/api/auth/session',
    '/login',
    'https://evil.example',
  ])
    assert.equal(returnPath(path), '/app/chat');
  for (const url of [
    'http://web.example',
    'https://user:password@web.example',
    'https://web.example/path',
    'https://web.example?query=1',
  ]) {
    assert.throws(() =>
      blotConfiguration({
        NODE_ENV: 'test',
        AUTH_SECRET: 's'.repeat(48),
        AUTH_URL: url,
        BLOT_AUTH_URL: 'https://blot.example/login',
      }),
    );
  }
});

test('Internal Next.js localhost uses only the configured public callback host', () => {
  const app = new URL('https://web.blot.example');
  const request = new Request(
    'http://localhost:3000/api/auth/blot/callback?state=test',
    { headers: { host: app.host, 'x-forwarded-proto': 'https' } },
  );
  assert.equal(callbackURL(request, app).origin, app.origin);
  assert.equal(
    callbackURL(request, app).pathname,
    '/app/api/auth/blot/callback',
  );
  assert.throws(() =>
    callbackURL(
      new Request(request.url, { headers: { host: 'attacker.example' } }),
      app,
    ),
  );
  assert.throws(() =>
    callbackURL(
      new Request(request.url, {
        headers: { host: app.host, 'x-forwarded-proto': 'http' },
      }),
      app,
    ),
  );
});

test('Only a verified Ori account with the token owner becomes a web identity', async () => {
  const owner = randomUUID();
  let exchanged = 0;
  const account = {
    id: owner,
    email: 'test@example.org',
    name: 'Ori Owner',
    verified: true,
    avatarURL: null,
  };
  const tokens = {
    ownerID: owner,
    accessToken: 't'.repeat(43),
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  };
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    assert.equal(init?.redirect, 'error');
    assert.equal(init?.cache, 'no-store');
    if (url.pathname.endsWith('/browser/token')) {
      exchanged++;
      const body = JSON.parse(String(init?.body));
      assert.equal(body.clientID, 'blot-web');
      assert.equal(body.redirectURI, configuration.redirectURI);
      return Response.json(tokens);
    }
    assert.equal(
      new Headers(init?.headers).get('Authorization'),
      `Bearer ${tokens.accessToken}`,
    );
    return Response.json(account);
  };
  const client = new BlotAccountClient(configuration, fetcher);
  assert.equal(
    (await client.exchange('c'.repeat(43), 'v'.repeat(43))).account.id,
    owner,
  );
  assert.equal(exchanged, 1);
  account.id = randomUUID();
  await assert.rejects(client.exchange('c'.repeat(43), 'v'.repeat(43)));
  account.id = owner;
  account.verified = false;
  await assert.rejects(client.profile(tokens.accessToken));
  const denied = new BlotAccountClient(
    configuration,
    async () => new Response(null, { status: 401 }),
  );
  await assert.rejects(
    denied.profile(tokens.accessToken),
    (error: unknown) =>
      error instanceof BlotAccountError && error.status === 401,
  );
});
