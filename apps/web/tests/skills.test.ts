import { expect, test } from '@playwright/test';
import { generateId } from 'ai';

const writingCoachId = '10000000-0000-4000-8000-000000000001';

test.describe('skills library', () => {
  const customSkillName = `Concise ${generateId(6)}`;

  test.afterEach(async ({ page }) => {
    await page.request.delete(`/app/api/skills/${writingCoachId}/installation`);
    const response = await page.request.get('/app/api/skills');
    if (!response.ok()) {
      return;
    }
    const skills = (await response.json()) as Array<{
      id: string;
      name: string;
      source: string;
    }>;
    const custom = skills.find(
      (skill) =>
        skill.source === 'custom' &&
        (skill.name === customSkillName ||
          skill.name === `${customSkillName} Updated`),
    );
    if (custom) {
      await page.request.delete(`/app/api/skills/${custom.id}`);
    }
  });

  test('installs, uses, and manages skills', async ({ page }) => {
    await page.goto('/app/plugins');
    await expect(page.getByRole('heading', { name: 'Skills' })).toBeVisible();
    await expect(page.getByText('No skills installed yet.')).toBeVisible();

    await page.getByRole('button', { name: 'Install Writing Coach' }).click();
    await expect(
      page.getByRole('button', { name: 'Writing Coach', exact: true }),
    ).toBeVisible();

    await page.goto('/app/chat');
    await page
      .getByTestId('multimodal-input')
      .fill('Use the Writing Coach skill to polish this: we launch tomorrow');
    const chatResponse = page.waitForResponse((response) =>
      response.url().includes('/app/api/chat'),
    );
    await page.getByTestId('send-button').click();
    await (await chatResponse).finished();
    await expect(
      page.getByText('Used skill: Writing Coach', { exact: true }),
    ).toBeVisible();
    await expect(page.getByText('We launch tomorrow.')).toBeVisible();

    await page.goto('/app/plugins');
    await page.getByRole('button', { name: 'Remove Writing Coach' }).click();
    await expect(page.getByText('No skills installed yet.')).toBeVisible();

    await page.getByRole('button', { name: 'Create', exact: true }).click();
    await page.getByLabel('Name').fill(customSkillName);
    await page
      .getByLabel('Description')
      .fill('Makes product updates concise and clear.');
    await page
      .getByLabel('When to use')
      .fill('Use for product update messages.');
    await page
      .getByLabel('Instructions')
      .fill('Preserve facts and produce a concise update.');
    await page.getByRole('button', { name: 'Create skill' }).click();
    await expect(
      page.getByRole('dialog').getByText(customSkillName, { exact: true }),
    ).toBeVisible();

    await page.getByRole('button', { name: 'Edit', exact: true }).click();
    await page.getByLabel('Name').fill(`${customSkillName} Updated`);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(
      page
        .getByRole('dialog')
        .getByText(`${customSkillName} Updated`, { exact: true }),
    ).toBeVisible();

    await page.getByRole('button', { name: 'Delete', exact: true }).click();
    await page
      .getByRole('button', { name: 'Delete skill', exact: true })
      .click();
    await expect(
      page.getByRole('button', {
        name: `${customSkillName} Updated`,
        exact: true,
      }),
    ).not.toBeVisible();
  });

  test('supports mobile layout and dark theme', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(() => {
      localStorage.setItem('theme', 'dark');
    });
    await page.goto('/app/plugins');

    await expect(page.locator('html')).toHaveClass(/dark/);
    await expect(page.getByRole('heading', { name: 'Skills' })).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Create', exact: true }),
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
