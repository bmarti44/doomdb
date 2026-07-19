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
  assert.equal(newGameCalls, 0, 'skill menu allocated a game before confirmation');
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
  assert.equal(newGameCalls, 1);
  assert.deepEqual(newGameBody, {p_skill: 4});
  process.stdout.write('PASS PLAY-MENU title=1 main=1 skill=4 windowed=1\n');
} finally {
  await browser.close();
}
