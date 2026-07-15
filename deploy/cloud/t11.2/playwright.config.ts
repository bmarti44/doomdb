import {defineConfig} from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: 'cloud-browser.spec.ts',
  forbidOnly: true,
  retries: 0,
  workers: 1,
  timeout: 3_600_000,
  reporter: [['json', {outputFile: '/tmp/doomdb-t112-playwright.json'}]],
  use: {
    browserName: 'chromium',
    locale: 'en-US',
    timezoneId: 'UTC',
    colorScheme: 'dark',
    deviceScaleFactor: 1,
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
    bypassCSP: false,
    ignoreHTTPSErrors: false
  }
});
