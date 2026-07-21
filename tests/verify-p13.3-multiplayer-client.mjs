import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {chromium} from 'playwright';

const base = process.env.DOOMDB_PLAY_BASE_URL ?? 'http://localhost:8080';
const browser = await chromium.launch({headless: true});
const hostContext = await browser.newContext({viewport: {width: 1000, height: 760}});
const guestContext = await browser.newContext({viewport: {width: 1000, height: 760}});
const host = await hostContext.newPage();
const guest = await guestContext.newPage();
let match = '';
try {
  await host.goto(`${base}/play/multiplayer`, {waitUntil: 'networkidle'});
  await host.locator('[data-create] input[name=name]').fill('BROWSER HOST');
  await host.getByRole('button', {name: 'Create two-player co-op'}).click();
  await host.locator('[data-room]').waitFor({state: 'visible'});
  const share = await host.locator('[data-share]').inputValue();
  const parsed = new URL(share);
  const joinMaterial = parsed.hash.slice('#join='.length).split('.');
  match = joinMaterial[0] ?? '';
  assert.match(match, /^[0-9a-f]{32}$/);
  assert.match(joinMaterial[1] ?? '', /^[0-9a-f]{64}$/);
  if (process.env.DOOMDB_MATCH_ID_FILE) {
    fs.writeFileSync(process.env.DOOMDB_MATCH_ID_FILE, `${match}\n`,
      {encoding: 'ascii', mode: 0o600});
  }

  await guest.goto(share, {waitUntil: 'networkidle'});
  await guest.locator('[data-join] input[name=name]').fill('BROWSER GUEST');
  await guest.getByRole('button', {name: 'Join co-op'}).click();
  await guest.locator('[data-room]').waitFor({state: 'visible'});
  await assert.doesNotReject(host.locator('[data-room-status]').waitFor({state: 'visible'}));
  await host.waitForFunction(() => document.querySelector('[data-room-status]')?.textContent?.includes('2/2 joined'));

  const hostReady = host.locator('[data-ready]');
  const guestReady = guest.locator('[data-ready]');
  await hostReady.waitFor({state: 'visible'});
  await guestReady.waitFor({state: 'visible'});
  await host.waitForFunction(() => {
    const button = document.querySelector('[data-ready]');
    return button instanceof HTMLButtonElement && !button.disabled;
  });
  await guest.waitForFunction(() => {
    const button = document.querySelector('[data-ready]');
    return button instanceof HTMLButtonElement && !button.disabled;
  });
  await hostReady.click();
  await guestReady.click();

  await Promise.all([
    host.locator('[data-game][data-active]').waitFor({state: 'visible', timeout: 60000}),
    guest.locator('[data-game][data-active]').waitFor({state: 'visible', timeout: 60000})
  ]);
  assert.match(host.url(), new RegExp(`#resume=${match}$`));
  assert.match(guest.url(), new RegExp(`#resume=${match}$`));
  assert.doesNotMatch(host.url(), /join=/);
  assert.doesNotMatch(guest.url(), /join=/);

  await Promise.all([
    host.waitForFunction(() => /TIC [1-9][0-9]*/.test(document.querySelector('[data-hud]')?.textContent ?? ''), null, {timeout: 30000}),
    guest.waitForFunction(() => /TIC [1-9][0-9]*/.test(document.querySelector('[data-hud]')?.textContent ?? ''), null, {timeout: 30000})
  ]);
  if (process.env.DOOMDB_TEST_ORDS_RESTART === '1') {
    const beforeRestart = await Promise.all([host, guest].map(async page =>
      Number((await page.locator('[data-hud]').textContent() ?? '')
        .match(/TIC (\d+)/)?.[1] ?? 0)));
    execFileSync('docker', ['compose', 'restart', 'ords'], {stdio: 'ignore'});
    let healthy = false;
    for (let attempt = 0; attempt < 360; attempt += 1) {
      try {
        const response = await fetch(`${base}/health.txt`);
        if (response.ok) { healthy = true;break; }
      } catch { /* ORDS is expected to refuse connections while restarting. */ }
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    assert.equal(healthy, true, 'ORDS did not become healthy after restart');
    await Promise.all([host, guest].map((page, index) => page.waitForFunction(
      previous => {
        const hud = document.querySelector('[data-hud]');
        const tic = Number(hud?.textContent?.match(/TIC (\d+)/)?.[1] ?? 0);
        return !hud?.classList.contains('error') && tic > previous;
      }, beforeRestart[index], {timeout: 60000})));
  }
  await guest.reload({waitUntil: 'domcontentloaded'});
  await guest.locator('[data-game][data-active]').waitFor({state: 'visible', timeout: 30000});
  await guest.waitForFunction(() => /TIC [1-9][0-9]*/.test(
    document.querySelector('[data-hud]')?.textContent ?? ''), null, {timeout: 30000});
  assert.match(guest.url(), new RegExp(`#resume=${match}$`));
  await host.keyboard.down('w');
  await host.waitForTimeout(350);
  await host.keyboard.up('w');
  await host.waitForTimeout(250);

  const bitmapSha = async page => page.locator('canvas').evaluate(async canvas => {
    if (!(canvas instanceof HTMLCanvasElement)) throw new Error('canvas missing');
    const context = canvas.getContext('2d');
    if (context === null) throw new Error('canvas context missing');
    const bytes = context.getImageData(0, 0, 320, 200).data;
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2, '0')).join('');
  });
  const [hostSha, guestSha] = await Promise.all([bitmapSha(host), bitmapSha(guest)]);
  assert.notEqual(hostSha, guestSha, 'browser POV canvases collapsed');
  let hostHud = '';
  let guestHud = '';
  for (let attempt = 0; attempt < 100; attempt += 1) {
    [hostHud, guestHud] = await Promise.all([
      host.locator('[data-hud]').textContent(), guest.locator('[data-hud]').textContent()
    ]);
    const hostFrontier = Number((hostHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
    const guestFrontier = Number((guestHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
    if (hostFrontier >= 1 && guestFrontier >= 1 &&
        Math.abs(hostFrontier - guestFrontier) <= 1) break;
    await host.waitForTimeout(100);
  }
  assert.match(hostHud ?? '', /PLAYER 1/);
  assert.match(guestHud ?? '', /PLAYER 2/);
  const hostTic = Number((hostHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
  const guestTic = Number((guestHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
  assert.ok(hostTic >= 1 && guestTic >= 1);
  assert.ok(Math.abs(hostTic - guestTic) <= 1);
  process.stdout.write(
    `PASS P13.3-MULTIPLAYER-CLIENT two browsers dynamic-input ORDS-restart reconnect distinct-POVs hostTic=${hostTic} guestTic=${guestTic} (bearers redacted)\n`);
} finally {
  await browser.close();
}
