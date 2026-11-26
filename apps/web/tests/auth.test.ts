import { expect, test } from '@playwright/test';

test.use({ storageState: { cookies: [], origins: [] } });

test('web login starts the shared Ori PKCE flow', async ({ request }) => {
  const response = await request.get(
    '/app/api/auth/blot/start?callbackUrl=%2Fprojects',
    { maxRedirects: 0 },
  );
  expect(response.status()).toBe(307);
  const target = new URL(response.headers().location);
  expect(target.origin).toBe(
    new URL(process.env.BLOT_AUTH_URL || 'http://127.0.0.1:3000/login').origin,
  );
  expect(target.pathname).toBe('/login');
  expect(target.searchParams.get('client_id')).toBe('blot-web');
  expect(target.searchParams.get('code_challenge_method')).toBe('S256');
  expect(target.searchParams.has('code_verifier')).toBe(false);
});

test('registration uses the same Ori account service', async ({ request }) => {
  const response = await request.get('/app/register', { maxRedirects: 0 });
  expect(response.status()).toBe(307);
  expect(response.headers().location).toContain('intent=register');
});

test('a callback without a browser attempt fails closed', async ({ page }) => {
  await page.goto(
    `/app/api/auth/blot/callback?code=${'c'.repeat(43)}&state=${'s'.repeat(43)}`,
  );
  await expect(page).toHaveURL(/\/login\?error=blot/);
  await expect(
    page.getByRole('heading', { name: 'Не удалось завершить вход в Ori' }),
  ).toBeVisible();
});
