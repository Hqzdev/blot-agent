import { expect, test } from '@playwright/test';
import { generateId } from 'ai';

test.describe('projects', () => {
  let projectId: string | undefined;

  test.afterEach(async ({ page }) => {
    if (projectId) {
      await page.request.delete(`/app/api/projects/${projectId}`);
    }
  });

  test('manages a project, its chat, and a source', async ({ page }) => {
    const originalName = `Launch ${generateId(6)}`;
    const renamedName = `Product ${generateId(6)}`;

    await page.goto('/app/projects');
    await page.getByRole('button', { name: 'New', exact: true }).click();
    await page
      .getByRole('textbox', { name: 'Project name' })
      .fill(originalName);
    await page.getByRole('button', { name: 'Create project' }).click();
    await expect(page).toHaveURL(/\/projects\/[0-9a-f-]{36}$/);
    projectId = new URL(page.url()).pathname.split('/').at(-1);
    await expect(
      page.getByRole('heading', { name: originalName }),
    ).toBeVisible();

    await page.getByRole('button', { name: 'Project menu' }).click();
    await page.getByRole('menuitem', { name: 'Rename' }).click();
    await page
      .getByRole('dialog', { name: 'Rename project' })
      .getByRole('textbox')
      .fill(renamedName);
    await page.getByRole('button', { name: 'Rename', exact: true }).click();
    await expect(
      page.getByRole('heading', { name: renamedName }),
    ).toBeVisible();

    await page.getByRole('tab', { name: 'Sources' }).click();
    const fileChooserPromise = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Add source', exact: true }).click();
    const fileChooser = await fileChooserPromise;
    await fileChooser.setFiles({
      name: 'launch-notes.md',
      mimeType: 'text/markdown',
      buffer: Buffer.from('The launch date is September 15.'),
    });
    await expect(page.getByText('launch-notes.md')).toBeVisible();
    await page.getByRole('button', { name: 'Delete launch-notes.md' }).click();
    await expect(page.getByText('launch-notes.md')).not.toBeVisible();

    await page
      .getByRole('textbox', { name: `New chat in ${renamedName}` })
      .fill('Create a concise launch checklist');
    const chatResponse = page.waitForResponse((response) =>
      response.url().includes('/app/api/chat'),
    );
    await page.getByRole('button', { name: 'Start chat' }).click();
    await expect(page).toHaveURL(
      new RegExp(`/app/projects/${projectId}/chat/[0-9a-f-]{36}$`),
    );
    await chatResponse;
    const openSidebar = page.getByRole('button', { name: 'Open sidebar' });
    if (await openSidebar.isVisible()) {
      await openSidebar.click();
    }
    await expect(page.getByText(renamedName, { exact: true })).toBeVisible();

    await page.goto('/app/projects');
    await page
      .getByRole('textbox', { name: 'Search projects' })
      .fill(renamedName);
    const projectCard = page
      .locator('main')
      .last()
      .getByRole('link', { name: new RegExp(renamedName) });
    await expect(projectCard).toBeVisible();
    await projectCard.click();
    await page.getByRole('button', { name: 'Project menu' }).click();
    await page.getByRole('menuitem', { name: 'Delete' }).click();
    await page.getByRole('button', { name: 'Delete project' }).click();
    projectId = undefined;
    await expect(page).toHaveURL('/app/projects');
    await expect(
      page.getByRole('heading', { name: 'No projects yet' }),
    ).toBeVisible();
  });
});
