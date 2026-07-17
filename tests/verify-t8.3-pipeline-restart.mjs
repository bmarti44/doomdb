import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('pipeline active'), null, {timeout: 120_000});

  // Exhaust the bounded async retry budget after a session is live. This is
  // the deployment-interruption shape that formerly looked like dead keys.
  await page.route(/\/(SUBMIT_STEP|POLL_FRAME)$/, route => route.abort('connectionfailed'));
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('Press R'), null, {timeout: 10_000});
  assert.match(await page.locator('[data-doom-status]').innerText(), /pipeline stopped/i);

  const restarted = page.waitForEvent('domcontentloaded');
  await page.keyboard.press('KeyR');
  await restarted;
  process.stdout.write('PASS T8.3-PIPELINE-RESTART (failure visible, KeyR reloads)\n');
} finally {
  await browser.close();
}
