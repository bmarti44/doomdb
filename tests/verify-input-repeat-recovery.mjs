import assert from 'node:assert/strict';
import fs from 'node:fs';
import {chromium} from 'playwright';

const root = new URL('../', import.meta.url);
const inputSource = fs.readFileSync(
  new URL('client/dist/play/input.js', root), 'utf8');
const browser = await chromium.launch({headless: true});
try {
  const page = await browser.newPage();
  await page.route('http://doom-input.test/**', async route => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname === '/input.js') {
      await route.fulfill({
        status: 200,
        contentType: 'text/javascript',
        body: inputSource,
      });
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: 'text/html',
      body: '<!doctype html><canvas id="game"></canvas>',
    });
  });
  await page.goto('http://doom-input.test/');
  const result = await page.evaluate(async () => {
    const {bindInput} = await import('/input.js');
    const emitted = [];
    const canvas = document.querySelector('#game');
    bindInput(canvas, new Map(), command => emitted.push({...command}),
      () => {}, () => {});
    const dispatch = (type, repeat) => {
      const event = new KeyboardEvent(type, {
        code: 'ArrowUp',
        key: 'ArrowUp',
        repeat,
        bubbles: true,
        cancelable: true,
      });
      return {
        accepted: window.dispatchEvent(event),
        defaultPrevented: event.defaultPrevented,
      };
    };
    const firstRepeat = dispatch('keydown', true);
    const afterFirstRepeat = emitted.map(command => command.forward);
    const ordinaryRepeat = dispatch('keydown', true);
    const afterOrdinaryRepeat = emitted.map(command => command.forward);
    const release = dispatch('keyup', false);
    return {
      firstRepeat,
      ordinaryRepeat,
      release,
      afterFirstRepeat,
      afterOrdinaryRepeat,
      final: emitted.map(command => command.forward),
    };
  });
  assert.equal(result.firstRepeat.defaultPrevented, true);
  assert.equal(result.firstRepeat.accepted, false);
  assert.deepEqual(result.afterFirstRepeat, [1],
    'first observed repeat did not recover the held forward key');
  assert.deepEqual(result.afterOrdinaryRepeat, [1],
    'ordinary held-key repeat emitted a redundant authority revision');
  assert.deepEqual(result.final, [1, 0],
    'keyup did not release the recovered forward command');
  assert.equal(result.release.defaultPrevented, true);
  console.log('PMLE_INPUT_REPEAT_RECOVERY|PASS|first_repeat=forward'
    +'|ordinary_repeat=suppressed|keyup=neutral');
} finally {
  await browser.close();
}
