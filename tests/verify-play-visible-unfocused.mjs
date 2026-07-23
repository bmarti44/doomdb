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
await page.route('**/doom_api/CREATE_MATCH', route =>
  route.fulfill({status: 503, contentType: 'application/json', body: '{}'}));

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('press Enter to start'), null, {timeout: 30_000});
  assert.ok(!requests.some(path => path.endsWith('/NEW_GAME')),
    'title screen allocated a game before player confirmation');
  const titleColors = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    const context = canvas?.getContext('2d');
    if (context === null || context === undefined) return 0;
    const pixels = context.getImageData(0, 0, 320, 200).data;
    const colors = new Set();
    for (let offset = 0; offset < pixels.length; offset += 4) {
      colors.add(`${pixels[offset]},${pixels[offset + 1]},${pixels[offset + 2]}`);
    }
    return colors.size;
  });
  assert.ok(titleColors >= 32, `title screen did not render (${titleColors} colors)`);
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'MAIN MENU');
  assert.ok(!requests.some(path => path.endsWith('/NEW_GAME')),
    'main menu allocated a game before New Game selection');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'CHOOSE SKILL LEVEL');
  assert.ok(!requests.some(path => path.endsWith('/CREATE_MATCH')),
    'skill menu allocated a match before confirmation');
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/play\/mle(?:\.html)?#solo=1&skill=3/, {timeout: 10_000});
  assert.ok(requests.some(path => path.endsWith('/CREATE_MATCH')),
    'confirmed skill did not create an MLE match');
  assert.ok(!requests.some(path => path.endsWith('/NEW_GAME') ||
    path.endsWith('/SUBMIT_STEP') || path.endsWith('/POLL_FRAME')),
  'production single-player path called a legacy OJVM endpoint');
  process.stdout.write('PASS PLAY-VISIBLE-UNFOCUSED mle-solo=1 legacy-calls=0\n');
} finally {
  await browser.close();
}
