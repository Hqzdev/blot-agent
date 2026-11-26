import { expect, test } from '@playwright/test';

test.describe('images', () => {
  test('uses a style prompt and starts a new image chat', async ({ page }) => {
    await page.goto('/app/images');

    await expect(
      page.getByRole('heading', { name: 'Images', exact: true }),
    ).toBeVisible();
    await page.getByRole('button', { name: 'Use Anime style' }).click();

    const prompt = page.getByRole('textbox', {
      name: 'Describe a new image',
    });
    await expect(prompt).toHaveValue(/anime character portrait/i);
    await page.getByRole('button', { name: 'Create image' }).click();

    await expect(page).toHaveURL(/\/chat\/[0-9a-f-]+$/);
    await expect(
      page.getByText(/Create an image:.*anime character portrait/i),
    ).toBeVisible();
  });

  test('supports mobile layout and dark theme', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(() => {
      localStorage.setItem('theme', 'dark');
    });
    await page.goto('/app/images');

    await expect(page.locator('html')).toHaveClass(/dark/);
    await expect(
      page.getByRole('heading', { name: 'Images', exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Create an image' }),
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'My images' }),
    ).toBeVisible();
    await expect
      .poll(() =>
        page.evaluate(
          () => document.documentElement.scrollWidth - window.innerWidth,
        ),
      )
      .toBeLessThanOrEqual(1);
  });
});
