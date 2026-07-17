import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
await page.addInitScript(() => {
  window.__doomTrace = [];
  for (const name of ['input', 'submit', 'decoded', 'present']) {
    addEventListener(`doom:${name}`, event => {
      window.__doomTrace.push({name, ...event.detail});
    });
  }
});

try {
  await page.goto(root, {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('pipeline active'), null, {timeout: 120_000});
  await page.waitForTimeout(250);

  const hashWeapon = () => page.evaluate(async () => {
    const context = document.querySelector('canvas').getContext('2d');
    const bytes = context.getImageData(72, 92, 176, 76).data;
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    return Array.from(digest, value => value.toString(16).padStart(2, '0')).join('');
  });

  await page.keyboard.down('KeyW');
  await page.waitForTimeout(180);
  await page.keyboard.up('KeyW');
  await page.waitForTimeout(300);
  await page.keyboard.down('ControlLeft');
  const weaponHashes = [];
  for (let sample = 0; sample < 18; sample += 1) {
    weaponHashes.push(await hashWeapon());
    await page.waitForTimeout(24);
  }
  await page.keyboard.up('ControlLeft');
  await page.waitForTimeout(600);

  const trace = await page.evaluate(() => window.__doomTrace);
  const movementInput = trace.find(row => row.name === 'input' && row.command.forward === 1);
  assert.ok(movementInput, 'W did not reach the thin-client command register');
  const movementSubmit = trace.find(row => row.name === 'submit' && row.at >= movementInput.at &&
    row.command.forward === 1);
  assert.ok(movementSubmit, 'movement command was not submitted');
  const decoded = trace.find(row => row.name === 'decoded' && row.sequence === movementSubmit.sequence);
  const presented = trace.find(row => row.name === 'present' && row.sequence === movementSubmit.sequence);
  assert.ok(decoded && presented, 'movement command did not reach a correlated frame and paint');
  const latency = {
    inputToSubmitMs: movementSubmit.at - movementInput.at,
    submitToDecodeMs: decoded.at - movementSubmit.at,
    decodeToPaintMs: presented.at - decoded.at,
    inputToPaintMs: presented.at - movementInput.at
  };
  assert.ok(latency.inputToSubmitMs <= 70, `input scheduling latency ${latency.inputToSubmitMs}`);
  assert.ok(latency.inputToPaintMs <= 250, `input-to-correlated-paint latency ${latency.inputToPaintMs}`);
  assert.ok(new Set(weaponHashes).size >= 2, 'FIRE produced no visible weapon animation');

  process.stdout.write(`PASS T8.3-LIVE-CLIENT ${JSON.stringify({latency,
    weaponFrames:new Set(weaponHashes).size,presented:trace.filter(row=>row.name==='present').length})}\n`);
} finally {
  await browser.close();
}
