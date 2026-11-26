import { timingSafeEqual } from 'node:crypto';
import { webPath } from '../web-path';

export function trustedURL(value: string, path = '/') {
  const url = new URL(value);
  if (
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname !== path ||
    !(
      url.protocol === 'https:' ||
      (url.protocol === 'http:' &&
        ['localhost', '127.0.0.1'].includes(url.hostname))
    )
  )
    throw new Error('Invalid Blot authentication configuration');
  return url;
}

export function blotConfiguration(environment = process.env) {
  const development = environment.NODE_ENV !== 'production';
  const login = trustedURL(
    environment.BLOT_AUTH_URL ||
      (development ? 'http://127.0.0.1:3000/login' : ''),
    '/login',
  );
  const app = trustedURL(
    environment.AUTH_URL || (development ? 'http://127.0.0.1:3001' : ''),
  );
  const account = trustedURL(
    environment.BLOT_ACCOUNT_SERVICE_URL || login.origin,
  );
  const secret = environment.AUTH_SECRET;
  if (!secret || secret.length < 32)
    throw new Error('AUTH_SECRET must contain at least 32 characters');
  return {
    login,
    app,
    account,
    secret,
    redirectURI: new URL(webPath('/api/auth/blot/callback'), app).href,
  };
}

export function returnPath(value: unknown): string {
  if (
    typeof value !== 'string' ||
    !value.startsWith('/') ||
    value.startsWith('//') ||
    /[\\\r\n]/.test(value)
  )
    return webPath('/chat');
  const url = new URL(value, 'https://blot.invalid');
  const path = url.pathname.replace(/^\/app(?=\/|$)/, '') || '/';
  if (
    url.origin !== 'https://blot.invalid' ||
    /^\/(api|login|register|auth)(\/|$)/.test(path)
  )
    return webPath('/chat');
  return webPath(url.pathname + url.search + url.hash);
}

export function trustedProxy(request: Request): boolean {
  const expected = process.env.BLOT_WEB_PROXY_SECRET;
  const actual = request.headers.get('x-blot-proxy-secret');
  return Boolean(
    expected &&
      actual &&
      Buffer.byteLength(actual) === Buffer.byteLength(expected) &&
      timingSafeEqual(Buffer.from(actual), Buffer.from(expected)),
  );
}

export function callbackURL(request: Request, app: URL): URL {
  const url = new URL(request.url);
  const host =
    request.headers.get('x-forwarded-host') ||
    request.headers.get('host') ||
    url.host;
  const protocol = request.headers.get('x-forwarded-proto');
  if (
    !trustedProxy(request) &&
    (host !== app.host || (protocol && protocol !== app.protocol.slice(0, -1)))
  )
    throw new Error('Unexpected Blot callback host');
  // Next.js can expose an internal localhost origin while preserving the public Host.
  url.host = app.host;
  url.protocol = app.protocol;
  url.port = app.port;
  url.pathname = webPath(url.pathname);
  return url;
}
