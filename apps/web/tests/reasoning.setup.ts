import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test as setup } from '@playwright/test';
import { ChatPage } from './pages/chat';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const reasoningFile = path.join(
  testDirectory,
  '../playwright/.reasoning/session.json',
);

setup('switch to reasoning model', async ({ page }) => {
  const chatPage = new ChatPage(page);
  await chatPage.createNewChat();

  await chatPage.chooseModelFromSelector('chat-model-reasoning');

  await expect(chatPage.getSelectedModel()).resolves.toEqual('Teya V1 Max');

  await page.waitForTimeout(1000);
  await page.context().storageState({ path: reasoningFile });
});
