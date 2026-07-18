import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
const requests = [];

await page.addInitScript(() => {
  // Reproduce a normal Chrome navigation where the visible document loads
  // while browser chrome or another window owns focus.
  Document.prototype.hasFocus = () => false;
});
page.on('request', request => {
  if (request.method() === 'POST') requests.push(new URL(request.url()).pathname);
});

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('pipeline active'), null, {timeout: 120_000});
  assert.ok(requests.some(path => path.endsWith('/SUBMIT_STEP')),
    'visible unfocused page never submitted a gameplay tic');
  assert.ok(requests.some(path => path.endsWith('/POLL_FRAME')),
    'visible unfocused page never polled a gameplay frame');
  process.stdout.write('PASS PLAY-VISIBLE-UNFOCUSED\n');
} finally {
  await browser.close();
}
