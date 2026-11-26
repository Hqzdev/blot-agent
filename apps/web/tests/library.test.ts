import { expect, test } from '@playwright/test';
import { generateId } from 'ai';

test.describe('library', () => {
  const marker = `Library-${generateId(6)}`;

  test.afterEach(async ({ page }) => {
    const activeResponse = await page.request.get(
      `/app/api/library/items?deleted=false&direction=desc&limit=100&query=${encodeURIComponent(marker)}&sort=modified&tab=all`,
    );
    if (activeResponse.ok()) {
      const active = (await activeResponse.json()) as {
        items: Array<{ id: string }>;
      };
      if (active.items.length > 0) {
        await page.request.post('/app/api/library/items/bulk', {
          data: {
            action: 'trash',
            ids: active.items.map((item) => item.id),
          },
        });
      }
    }
    const deletedResponse = await page.request.get(
      `/app/api/library/items?deleted=true&direction=desc&limit=100&query=${encodeURIComponent(marker)}&sort=modified&tab=all`,
    );
    if (deletedResponse.ok()) {
      const deleted = (await deletedResponse.json()) as {
        items: Array<{ id: string }>;
      };
      if (deleted.items.length > 0) {
        await page.request.post('/app/api/library/items/bulk', {
          data: {
            action: 'permanent',
            ids: deleted.items.map((item) => item.id),
          },
        });
      }
    }
  });

  test('manages folders, files, views, search, move, and trash', async ({
    page,
  }) => {
    const folderName = `${marker}-Folder`;
    const originalName = `${marker}.txt`;
    const renamedName = `${marker}-Renamed.txt`;

    await page.goto('/app/library');
    await page.getByRole('button', { name: 'New', exact: true }).click();
    await page.getByRole('menuitem', { name: 'Folder', exact: true }).click();
    await page.getByRole('dialog').getByRole('textbox').fill(folderName);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(
      page.getByRole('button', { name: folderName, exact: true }),
    ).toBeVisible();

    await page.getByRole('button', { name: folderName, exact: true }).click();
    await expect(
      page.getByRole('navigation').getByRole('button', { name: folderName }),
    ).toBeVisible();

    const fileChooserPromise = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'New', exact: true }).click();
    await page.getByRole('menuitem', { name: 'Upload', exact: true }).click();
    const fileChooser = await fileChooserPromise;
    await fileChooser.setFiles({
      buffer: Buffer.from('Library integration test'),
      mimeType: 'text/plain',
      name: originalName,
    });
    await expect(page.getByText(originalName, { exact: true })).toBeVisible();

    await page
      .getByRole('button', { name: `Actions for ${originalName}` })
      .click();
    await page.getByRole('menuitem', { name: 'Rename' }).click();
    await page
      .getByRole('dialog')
      .getByRole('textbox')
      .fill(`${marker}-Renamed`);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(page.getByText(renamedName, { exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Grid view' }).click();
    await expect(
      page.getByRole('article').filter({ hasText: renamedName }),
    ).toBeVisible();
    await page.getByRole('button', { name: 'List view' }).click();

    await page.getByRole('button', { name: `Select ${renamedName}` }).click();
    await page.getByRole('button', { name: 'Move', exact: true }).click();
    await page.getByRole('button', { name: 'Move here' }).click();
    await expect(
      page.getByText(renamedName, { exact: true }),
    ).not.toBeVisible();

    await page.getByRole('textbox', { name: 'Search Library' }).fill(marker);
    await expect(page.getByText(renamedName, { exact: true })).toBeVisible();
    await expect(page.getByText(folderName, { exact: true })).toBeVisible();

    await page
      .getByRole('button', { name: `Actions for ${renamedName}` })
      .click();
    page.once('dialog', (dialog) => dialog.accept());
    await page.getByRole('menuitem', { name: 'Delete', exact: true }).click();
    await expect(
      page.getByText(renamedName, { exact: true }),
    ).not.toBeVisible();

    await page.getByRole('button', { name: 'Filter Library' }).click();
    await page
      .getByRole('menuitem', { name: 'Recently deleted', exact: true })
      .click();
    await expect(page.getByText(renamedName, { exact: true })).toBeVisible();
    await page
      .getByRole('button', { name: `Actions for ${renamedName}` })
      .click();
    await page.getByRole('menuitem', { name: 'Restore' }).click();
    await expect(
      page.getByText(renamedName, { exact: true }),
    ).not.toBeVisible();

    await page.getByRole('button', { name: 'Filter Library' }).click();
    await page
      .getByRole('menuitem', { name: 'Show all file types', exact: true })
      .click();
    await expect(page.getByText(renamedName, { exact: true })).toBeVisible();
  });

  test('supports mobile layout and dark theme', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(() => {
      localStorage.setItem('theme', 'dark');
    });
    await page.goto('/app/library');

    await expect(page.locator('html')).toHaveClass(/dark/);
    await expect(page.getByRole('heading', { name: 'Library' })).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'New', exact: true }),
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
