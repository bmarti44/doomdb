import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const frame = Buffer.alloc(320 * 200, 4);
const audio = Buffer.from('[]');
const payload = Buffer.alloc(140 + audio.length + frame.length);
payload.write('DMF3', 0, 'ascii');
payload.writeInt32BE(0, 4);
payload[8] = 0;
payload[9] = 0;
payload.write('0'.repeat(64), 10, 'ascii');
payload.write(createHash('sha256').update(frame).digest('hex'), 74, 'ascii');
payload.writeUInt16BE(audio.length, 138);
audio.copy(payload, 140);
frame.copy(payload, 140 + audio.length);

const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
await page.addInitScript(() => {
  window.__initialFrame = null;
  window.__canvasFingerprint = () => {
    const canvas = document.querySelector('canvas');
    if (canvas === null) return null;
    const bytes = canvas.getContext('2d').getImageData(0, 0, 320, 200).data;
    let hash = 0x811c9dc5;
    for (const byte of bytes) hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
    return hash.toString(16).padStart(8, '0');
  };
  addEventListener('doom:initial', event => {
    window.__initialFrame = {...event.detail, canvasFingerprint: window.__canvasFingerprint()};
  });
});
await page.route('**/doom_api/NEW_GAME', route => route.fulfill({
  status: 200,
  contentType: 'application/json',
  body: JSON.stringify({p_session: 'a'.repeat(32), p_payload: payload.toString('base64')})
}));
await page.route('**/doom_api/SUBMIT_STEP', route => route.abort());

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('press Enter to start'), null, {timeout: 30_000});
  const titleFingerprint = await page.evaluate(() => window.__canvasFingerprint());
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'MAIN MENU');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'CHOOSE SKILL LEVEL');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => window.__initialFrame !== null);
  const initial = await page.evaluate(() => window.__initialFrame);
  assert.deepEqual({tic: initial.tic, painted: initial.painted,
    canvasFingerprint: initial.canvasFingerprint},
  {tic: 0, painted: false, canvasFingerprint: titleFingerprint});
  process.stdout.write('PASS PLAY-INITIAL-FRAME tic-zero-suppressed=1 title-retained=1\n');
} finally {
  await browser.close();
}
