import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
let newGameBody;
let newGameCalls = 0;

await page.route('**/doom_api/NEW_GAME', async route => {
  newGameCalls += 1;
  newGameBody = route.request().postDataJSON();
  await route.fulfill({status: 503, contentType: 'application/json', body: '{}'});
});

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('press Enter to start'), null, {timeout: 30_000});
  assert.equal(newGameCalls, 0, 'title screen allocated a game');
  const fullscreen = page.locator('[data-doom-fullscreen]');
  await fullscreen.click();
  await page.waitForFunction(() => document.fullscreenElement
    ?.hasAttribute('data-doom-shell') && document.querySelector('[data-doom-fullscreen]')
      ?.getAttribute('aria-pressed') === 'true');
  assert.equal(await fullscreen.getAttribute('aria-pressed'), 'true');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => document.fullscreenElement === null &&
    document.querySelector('[data-doom-fullscreen]')?.getAttribute('aria-pressed') === 'false');
  assert.equal(await fullscreen.getAttribute('aria-pressed'), 'false');

  await page.locator('canvas').click({position: {x: 160, y: 100}});
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'MAIN MENU');
  assert.equal(newGameCalls, 0, 'main menu allocated a game');
  assert.equal(await page.evaluate(() => document.fullscreenElement), null,
    'title click unexpectedly entered fullscreen');

  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'CHOOSE SKILL LEVEL');
  assert.equal(await page.locator('[data-doom-menu] button[data-selected]').textContent(),
    'HURT ME PLENTY');
  // Selecting NEW GAME is explicit intent: the client overlaps the ~10 s
  // engine construction with the skill menu by speculatively allocating the
  // highlighted default skill. Title and main-menu lurkers allocate nothing.
  for (let waited = 0; newGameCalls === 0 && waited < 3000; waited += 100) {
    await page.waitForTimeout(100);
  }
  assert.equal(newGameCalls, 1, 'skill menu did not begin the speculative default-skill allocation');
  assert.deepEqual(newGameBody, {p_skill: 3});
  await page.keyboard.press('ArrowDown');
  assert.equal(await page.locator('[data-doom-menu] button[data-selected]').textContent(),
    'ULTRA-VIOLENCE');
  await page.keyboard.press('ArrowUp');
  const bounds = await page.locator('canvas').boundingBox();
  assert.ok(bounds, 'menu canvas has no pointer bounds');
  await page.mouse.click(bounds.x + bounds.width * 100 / 320,
    bounds.y + bounds.height * 118 / 200);
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('Game startup failed'));
  assert.equal(newGameCalls, 2, 'confirming a non-default skill must fall back to a fresh allocation');
  assert.deepEqual(newGameBody, {p_skill: 4});
  process.stdout.write('PASS PLAY-MENU title=1 main=1 skill=4 windowed=1 fullscreen-button=1 escape-exit=1\n');
} finally {
  await browser.close();
}
