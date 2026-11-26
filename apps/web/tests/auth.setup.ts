import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test as setup } from '@playwright/test';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const authFile = path.join(testDirectory, '../playwright/.auth/session.json');

setup(
  'authenticate with an isolated Ori test account',
  async ({ page, context }) => {
    const accessToken = process.env.BLOT_TEST_ACCESS_TOKEN;
    if (!accessToken)
      throw new Error(
        'Set BLOT_TEST_ACCESS_TOKEN for an isolated Ori test account before the authenticated E2E suite.',
      );
    const started = await context.request.get('/app/api/auth/blot/start', {
      maxRedirects: 0,
    });
    const login = new URL(started.headers().location);
    const accountOrigin = process.env.BLOT_ACCOUNT_SERVICE_URL || login.origin;
    const issued = await context.request.post(
      `${accountOrigin}/v1/auth/browser/code`,
      {
        headers: { Authorization: `Bearer ${accessToken}` },
        data: {
          clientID: 'blot-web',
          redirectURI: login.searchParams.get('redirect_uri'),
          codeChallenge: login.searchParams.get('code_challenge'),
        },
      },
    );
    expect(issued.ok()).toBeTruthy();
    const { code } = await issued.json();
    const callback = new URL(login.searchParams.get('redirect_uri') || '');
    callback.search = new URLSearchParams({
      code,
      state: login.searchParams.get('state') || '',
    }).toString();
    await page.goto(callback.href);
    await expect(page).toHaveURL((url) => url.pathname === '/app/chat');
    await context.storageState({ path: authFile });
  },
);
