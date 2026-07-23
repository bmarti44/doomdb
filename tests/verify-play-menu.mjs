import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
let createMatchBody;
let createMatchCalls = 0;

await page.route('**/doom_api/CREATE_MATCH', async route => {
  createMatchCalls += 1;
  createMatchBody = route.request().postDataJSON();
  await route.fulfill({status: 503, contentType: 'application/json', body: '{}'});
});

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('press Enter to start'), null, {timeout: 30_000});
  assert.equal(createMatchCalls, 0, 'title screen allocated a game');
  await assert.doesNotReject(() => page.locator('[data-doom-coop]').waitFor());
  assert.equal(await page.locator('[data-doom-coop]').textContent(), 'Co-op');
  assert.equal(await page.locator('[data-doom-multiplayer]').textContent(), 'Multiplayer');
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
  assert.equal(createMatchCalls, 0, 'main menu allocated a game');
  assert.equal(await page.evaluate(() => document.fullscreenElement), null,
    'title click unexpectedly entered fullscreen');

  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'CHOOSE SKILL LEVEL');
  assert.equal(await page.locator('[data-doom-menu] button[data-selected]').textContent(),
    'HURT ME PLENTY');
  assert.equal(createMatchCalls, 0, 'skill menu allocated before confirmation');
  await page.keyboard.press('ArrowDown');
  assert.equal(await page.locator('[data-doom-menu] button[data-selected]').textContent(),
    'ULTRA-VIOLENCE');
  await page.keyboard.press('ArrowUp');
  const bounds = await page.locator('canvas').boundingBox();
  assert.ok(bounds, 'menu canvas has no pointer bounds');
  await page.mouse.click(bounds.x + bounds.width * 100 / 320,
    bounds.y + bounds.height * 118 / 200);
  await page.waitForURL(/\/play\/mle(?:\.html)?#solo=1&skill=4/, {timeout: 10_000});
  for (let waited = 0; createMatchCalls === 0 && waited < 3000; waited += 100) {
    await page.waitForTimeout(100);
  }
  assert.equal(createMatchCalls, 1, 'confirmed skill did not create one MLE solo match');
  assert.deepEqual(createMatchBody, {
    p_game_mode: 'COOP', p_skill: 4, p_episode: 1, p_map: 1,
    p_display_name: 'PLAYER 1', p_max_players: 1
  });
  process.stdout.write('PASS PLAY-MENU title=1 main=1 skill=4 mle-solo=1 coop-button=1 multiplayer-button=1 windowed=1 fullscreen-button=1 escape-exit=1\n');
} finally {
  await browser.close();
}
