import { defineConfig, devices } from '@playwright/test';

import { config } from 'dotenv';

config({
  path: '.env.local',
});

const PORT = process.env.PORT || 3001;

const baseURL = process.env.AUTH_URL || `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: './tests',

  fullyParallel: true,

  forbidOnly: !!process.env.CI,

  retries: process.env.CI ? 2 : 1,

  workers: process.env.CI ? 1 : undefined,

  reporter: 'html',

  use: {
    baseURL,

    trace: 'on-first-retry',
  },

  timeout: 60 * 1000,
  expect: {
    timeout: 60 * 1000,
  },

  projects: [
    { name: 'auth', testMatch: /auth.test.ts/ },
    {
      name: 'setup:auth',
      testMatch: /auth.setup.ts/,
    },
    {
      name: 'setup:reasoning',
      testMatch: /reasoning.setup.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'chat',
      testMatch: /chat.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'reasoning',
      testMatch: /reasoning.test.ts/,
      dependencies: ['setup:reasoning'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.reasoning/session.json',
      },
    },
    {
      name: 'artifacts',
      testMatch: /artifacts.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'projects',
      testMatch: /projects.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'skills',
      testMatch: /skills.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'library',
      testMatch: /library.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
    {
      name: 'images',
      testMatch: /images.test.ts/,
      dependencies: ['setup:auth'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/session.json',
      },
    },
  ],

  webServer: {
    command: `pnpm dev --port ${PORT}`,
    url: baseURL,
    timeout: 120 * 1000,
    reuseExistingServer: !process.env.CI,
  },
});
