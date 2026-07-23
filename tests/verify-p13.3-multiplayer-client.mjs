import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {chromium} from 'playwright';

const base = process.env.DOOMDB_PLAY_BASE_URL ?? 'http://localhost:8080';
const performanceFrames = Number(process.env.DOOMDB_MULTIPLAYER_FRAMES ?? 0);
const enforcePerformance = process.env.DOOMDB_PERF_DIAGNOSTIC !== '1';
assert.ok(Number.isInteger(performanceFrames) && performanceFrames >= 0 &&
  performanceFrames <= 300);
const browser = await chromium.launch({headless: true});
const hostContext = await browser.newContext({viewport: {width: 1000, height: 760}});
const guestContext = await browser.newContext({viewport: {width: 1000, height: 760}});
for (const context of [hostContext, guestContext]) {
  await context.addInitScript(() => {
    performance.setResourceTimingBufferSize(2000);
    window.__doomMultiplayerTrace = [];
    for (const name of ['input', 'input-effective', 'submit', 'poll', 'ready', 'decoded', 'present']) {
      addEventListener(`doom:multiplayer-${name}`, event => {
        window.__doomMultiplayerTrace.push({name, ...event.detail});
      });
    }
  });
}
const host = await hostContext.newPage();
const guest = await guestContext.newPage();
let match = '';
try {
  await host.goto(`${base}/play/multiplayer`, {waitUntil: 'networkidle'});
  await host.locator('[data-create] input[name=name]').fill('BROWSER HOST');
  const requestedMode = process.env.DOOMDB_MATCH_MODE === 'DEATHMATCH'
    ? 'DEATHMATCH' : 'COOP';
  await host.locator('[data-create] select[name=mode]').selectOption(requestedMode);
  await host.getByRole('button', {name: 'Create two-player match'}).click();
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
  await guest.getByRole('button', {name: 'Join match'}).click();
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
  const earlyHuds=await Promise.all([host,guest].map(page=>page.locator('[data-hud]')
    .evaluate(element=>({text:element.textContent,error:element.classList.contains('error')}))));
  assert.notEqual(hostSha, guestSha,
    `browser POV canvases collapsed ${JSON.stringify(earlyHuds)}`);
  let hostHud = '';
  let guestHud = '';
  for (let attempt = 0; attempt < 300; attempt += 1) {
    [hostHud, guestHud] = await Promise.all([
      host.locator('[data-hud]').textContent(), guest.locator('[data-hud]').textContent()
    ]);
    const hostFrontier = Number((hostHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
    const guestFrontier = Number((guestHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
    if (hostFrontier >= 1 && guestFrontier >= 1 &&
        Math.abs(hostFrontier - guestFrontier) <= 4) break;
    await host.waitForTimeout(100);
  }
  assert.match(hostHud ?? '', /PLAYER 1/);
  assert.match(guestHud ?? '', /PLAYER 2/);
  const hostTic = Number((hostHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
  const guestTic = Number((guestHud ?? '').match(/TIC (\d+)/)?.[1] ?? 0);
  assert.ok(hostTic >= 1 && guestTic >= 1);
  assert.ok(Math.abs(hostTic - guestTic) <= 4,
    `browser frontiers diverged host=${hostTic} guest=${guestTic}`);
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
    const lag=Number(document.querySelector('[data-hud]')?.textContent
      ?.match(/LAG (\d+)/)?.[1] ?? 999);
    return lag<=4;
  },null,{timeout:30000})));
  let performanceSummary = '';
  if (performanceFrames > 0) {
    const starts = await Promise.all([host, guest].map(page => page.evaluate(() => ({
      count: window.__doomMultiplayerTrace.filter(row => row.name === 'present').length,
      at: performance.now()
    }))));
    const exerciseInput = async (page, key) => {
      for (let transition = 0; transition < 26; transition += 1) {
        if (transition % 2 === 0) await page.keyboard.down(key);
        else await page.keyboard.up(key);
        await page.waitForTimeout(180);
      }
      await page.keyboard.up(key);
    };
    try {
      await Promise.all([
        exerciseInput(host, 'w'), exerciseInput(guest, 'w'),
        ...[host, guest].map((page, index) => page.waitForFunction(
          ({start, count}) => window.__doomMultiplayerTrace
            .filter(row => row.name === 'present').length >= start + count,
          {start: starts[index].count, count: performanceFrames}, {timeout: 120000}))
      ]);
    } catch (cause) {
      const diagnostic = await Promise.all([host, guest].map(page => page.evaluate(() => {
        const presents = window.__doomMultiplayerTrace.filter(row => row.name === 'present');
        return {hud: document.querySelector('[data-hud]')?.textContent ?? '',
          totalPresents: presents.length, lastTic: presents.at(-1)?.tic ?? null};
      })));
      throw new Error(`multiplayer performance timeout ${JSON.stringify(diagnostic)}`,
        {cause});
    }
    const traces = await Promise.all([host, guest].map((page, index) =>
      page.evaluate(({start, count}) => {
        const all = window.__doomMultiplayerTrace;
        const presents = all.filter(row => row.name === 'present')
          .slice(start.count, start.count + count);
        const resources = performance.getEntriesByType('resource')
          .filter(row => row.startTime >= start.at && row.name.includes('/ords/'))
          .map(row => ({name: (new URL(row.name).pathname.split('/').filter(Boolean).at(-1) ?? '').toLowerCase(),
            queue: row.requestStart-row.startTime,
            ttfb: row.responseStart-row.requestStart,
            download: row.responseEnd-row.responseStart,
            duration: row.duration}));
        return {all, presents, resources};
      }, {start: starts[index], count: performanceFrames})));
    const percentile = (values, fraction) => {
      if (values.length === 0) return 0;
      const ordered = [...values].sort((a, b) => a - b);
      return ordered[Math.ceil(ordered.length * fraction) - 1];
    };
    const summaries = traces.map(({all, presents, resources}, slot) => {
      assert.equal(presents.length, performanceFrames);
      assert.equal(new Set(presents.map(row => row.tic)).size,
        performanceFrames, `player ${slot} repeated a measured tic`);
      for (let index = 1; index < presents.length; index += 1) {
        assert.equal(presents[index].tic, presents[index - 1].tic + 1,
          `player ${slot} skipped measured tic ${presents[index - 1].tic}`);
      }
      const measuredTics = new Set(presents.map(row => row.tic));
      const decodedTics = [...new Set(all.filter(row => row.name === 'decoded' &&
        measuredTics.has(row.tic))
        .map(row => row.tic))].sort((a, b) => a - b);
      for (let index = 1; index < decodedTics.length; index += 1) {
        assert.equal(decodedTics[index], decodedTics[index - 1] + 1,
          `player ${slot} authoritative decoded chain skipped tic ${decodedTics[index - 1]}`);
      }
      const gaps = presents.slice(1).map((row, index) => row.at - presents[index].at);
      const elapsed = presents.at(-1).at - presents[0].at;
      const fps = (presents.length - 1) * 1000 / elapsed;
      const inputs = all.filter(row => row.name === 'input' && row.at>=starts[slot].at);
      const applicable = new Map();
      for (const effective of all.filter(row => row.name === 'input-effective' &&
        measuredTics.has(row.effectiveTic))) {
        const prior=applicable.get(effective.effectiveTic);
        if (prior===undefined || effective.inputSequence>prior.inputSequence)
          applicable.set(effective.effectiveTic,effective);
      }
      const latencies = [...applicable.values()].map(effective => {
        const input = inputs.find(row => row.inputSequence === effective.inputSequence);
        const presented = presents.find(row => row.tic === effective.effectiveTic);
        return input === undefined || presented === undefined ? null : presented.at-input.at;
      }).filter(value => value !== null);
      assert.ok(latencies.length>=(enforcePerformance?20:0),
        `player ${slot} input overlay samples=${latencies.length}`);
      const p50 = percentile(gaps, .5), p95 = percentile(gaps, .95);
      const p999 = percentile(gaps, .999), paintMax = Math.max(...gaps);
      const measuredSubmits = all.filter(row => row.name === 'submit' &&
        measuredTics.has(row.tic));
      const submitGaps = measuredSubmits.slice(1)
        .map((row, index) => row.at - measuredSubmits[index].at);
      const server = measuredSubmits.map(row => {
        const decoded = all.find(candidate => candidate.name === 'decoded' &&
          candidate.tic === row.tic);
        return decoded === undefined ? null : decoded.at - row.at;
      }).filter(value => value !== null);
      const delivery = presents.map(row => {
        const polled = all.find(candidate => candidate.name === 'poll' &&
          candidate.tic === row.tic);
        const frameReady = all.find(candidate => candidate.name === 'ready' &&
          candidate.tic === row.tic);
        return polled === undefined || frameReady === undefined ? null :
          frameReady.at - polled.at;
      }).filter(value => value !== null);
      const decodePaint = presents.map(row => {
        const decoded = all.find(candidate => candidate.name === 'decoded' &&
          candidate.tic === row.tic);
        return decoded === undefined ? null : row.at - decoded.at;
      }).filter(value => value !== null);
      const inputP50=percentile(latencies,.5),inputP95=percentile(latencies,.95);
      const inputP999=percentile(latencies,.999);
      const inputMax=Math.max(...latencies);
      const worstGap=gaps.reduce((best,value,index)=>value>best.value?
        {value,tic:presents[index+1].tic}:best,{value:-1,tic:-1});
      const submitResources=resources.filter(row=>
        row.name.startsWith('submit_match') || row.name==='revise_match_input');
      const pollResources=resources.filter(row=>row.name==='poll_match_batch');
      const resourceTail=(rows,field)=>rows.length===0?0:percentile(rows.map(row=>row[field]),.95);
      const detail = `p${slot}=${fps.toFixed(2)}fps paint=${p50.toFixed(2)}/${p95.toFixed(2)}ms paint999/max=${p999.toFixed(2)}/${paintMax.toFixed(2)}ms submitGap=${percentile(submitGaps, .5).toFixed(2)}/${percentile(submitGaps, .95).toFixed(2)}ms submitDecode=${percentile(server, .5).toFixed(2)}/${percentile(server, .95).toFixed(2)}ms pollReady=${percentile(delivery, .5).toFixed(2)}/${percentile(delivery, .95).toFixed(2)}ms decodePaint=${percentile(decodePaint, .5).toFixed(2)}/${percentile(decodePaint, .95).toFixed(2)}ms input=${inputP50.toFixed(2)}/${inputP95.toFixed(2)}ms input999/max=${inputP999.toFixed(2)}/${inputMax.toFixed(2)}ms n=${latencies.length} worstPaint=${worstGap.tic}:${worstGap.value.toFixed(1)} net95=submit(q${resourceTail(submitResources,'queue').toFixed(1)},t${resourceTail(submitResources,'ttfb').toFixed(1)},d${resourceTail(submitResources,'download').toFixed(1)})/poll(q${resourceTail(pollResources,'queue').toFixed(1)},t${resourceTail(pollResources,'ttfb').toFixed(1)},d${resourceTail(pollResources,'download').toFixed(1)})`;
      if (enforcePerformance) {
        assert.ok(fps >= 30, `player ${slot} ${detail}`);
        assert.ok(p50 <= 33.3 && p95 <= 33.3, `player ${slot} ${detail}`);
        assert.ok(inputP50<=250 && inputP95<=250,
          `player ${slot} ${detail}`);
      }
      return detail;
    });
    performanceSummary = ` frames=${performanceFrames} ${summaries.join(' ')}`;
  }
  process.stdout.write(
    `PASS P13.3-MULTIPLAYER-CLIENT mode=${requestedMode} two browsers dynamic-input ${process.env.DOOMDB_TEST_ORDS_RESTART === '1' ? 'ORDS-restart ' : ''}reconnect distinct-POVs hostTic=${hostTic} guestTic=${guestTic}${performanceSummary} (bearers redacted)\n`);
} finally {
  await browser.close();
}
