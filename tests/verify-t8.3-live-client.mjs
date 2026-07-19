import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = process.env.DOOM_PLAY_URL ?? 'http://localhost:8080/play/';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
await page.addInitScript(() => {
  // Chromium's macOS headless shell rejects the native primitive with
  // WrongDocumentError. Keep the interaction and live pipeline real while
  // substituting only the browser-owned lock state for this wiring gate.
  let locked = null;
  Object.defineProperty(document, 'pointerLockElement', {
    configurable: true, get: () => locked
  });
  HTMLCanvasElement.prototype.requestPointerLock = function requestPointerLock() {
    locked = this;
    document.dispatchEvent(new Event('pointerlockchange'));
    return Promise.resolve();
  };
  document.exitPointerLock = () => {
    locked = null;
    document.dispatchEvent(new Event('pointerlockchange'));
  };
  Object.defineProperty(navigator, 'platform', {configurable: true, value: 'Linux x86_64'});
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
    ?.textContent?.includes('Enter for windowed'), null, {timeout: 30_000});
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'MAIN MENU');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-menu] h2')
    ?.textContent === 'CHOOSE SKILL LEVEL');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('[data-doom-status]')
    ?.textContent?.includes('pipeline active'), null, {timeout: 120_000});
  await page.waitForTimeout(250);

  const keyboardCapture = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    canvas.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}));
    const first = new KeyboardEvent('keydown',
      {code: 'ControlLeft', bubbles: true, cancelable: true});
    const repeated = new KeyboardEvent('keydown',
      {code: 'ControlLeft', repeat: true, bubbles: true, cancelable: true});
    const firstCancelled = !window.dispatchEvent(first);
    const repeatCancelled = !window.dispatchEvent(repeated);
    window.dispatchEvent(new KeyboardEvent('keyup',
      {code: 'ControlLeft', bubbles: true, cancelable: true}));
    return {canvasFocused: document.activeElement === canvas, firstCancelled, repeatCancelled};
  });
  assert.deepEqual(keyboardCapture,
    {canvasFocused: true, firstCancelled: true, repeatCancelled: true},
    'click-to-focus or held-key capture failed');

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

  await page.locator('canvas').click({position: {x: 160, y: 100}});
  await page.waitForFunction(() => document.pointerLockElement ===
    document.querySelector('canvas'), null, {timeout: 5_000});
  const mouseTraceStart = await page.evaluate(() => window.__doomTrace.length);
  await page.evaluate(() => {
    const movement = new MouseEvent('mousemove', {bubbles: true});
    Object.defineProperty(movement, 'movementX', {value: 80});
    document.dispatchEvent(movement);
  });
  await page.waitForTimeout(70);
  await page.locator('canvas').dispatchEvent('mousedown', {button: 0});
  await page.waitForTimeout(100);
  await page.locator('canvas').dispatchEvent('mouseup', {button: 0});
  await page.waitForTimeout(100);

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
  const mouseTrace = trace.slice(mouseTraceStart);
  assert.ok(mouseTrace.some(row => row.name === 'input' && row.command.turn !== 0),
    'captured relative mouse movement did not reach the command register');
  assert.ok(mouseTrace.some(row => row.name === 'input' && row.command.fire === 1),
    'captured left mouse button did not reach the command register');
  await page.keyboard.press('Escape');
  await page.evaluate(() => document.exitPointerLock());
  await page.waitForFunction(() => document.pointerLockElement === null);

  process.stdout.write(`PASS T8.3-LIVE-CLIENT ${JSON.stringify({latency,
    weaponFrames:new Set(weaponHashes).size,presented:trace.filter(row=>row.name==='present').length,
    mouseCaptured:true})}\n`);
} finally {
  await browser.close();
}
