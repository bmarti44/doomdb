import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync} from 'node:fs';
import {chromium} from '@playwright/test';

const url = process.argv[2];
const seconds = Number(process.argv[3] ?? '30');
const holdSeconds = Number(process.argv[4] ?? '0');
const fireDuringRoute = process.env.DOOMDB_PUBLIC_FIRE !== 'NO';
const turnDuringRoute = process.env.DOOMDB_PUBLIC_TURN === 'YES';
const injectedRttMs = Number(process.env.DOOMDB_PUBLIC_NETWORK_RTT_MS ?? '0');
const captureDir = process.env.DOOMDB_PUBLIC_CAPTURE_DIR;
if(captureDir!==undefined)mkdirSync(captureDir,{recursive:true});
if (!url || !Number.isFinite(seconds) || seconds < 10 || seconds > 300) {
  throw new Error(
    'usage: node measure-public-exact-fps.mjs URL [SECONDS] [HOLD_SECONDS]',
  );
}
if (!Number.isFinite(holdSeconds) || holdSeconds < 0 || holdSeconds > 300) {
  throw new Error('invalid post-measurement hold');
}
if (!Number.isFinite(injectedRttMs) || injectedRttMs < 0 ||
    injectedRttMs > 2_000) {
  throw new Error('invalid injected public-network RTT');
}
const browser = await chromium.launch();
const page = await browser.newPage({viewport: {width: 1280, height: 840}});
if (injectedRttMs > 0) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: injectedRttMs / 2,
    downloadThroughput: 10 * 1024 * 1024 / 8,
    uploadThroughput: 2 * 1024 * 1024 / 8,
    connectionType: 'cellular4g',
  });
}
const errors = [];
const apiFailures = [];
const exchangeRequests = new Map();
const exchangeResults = [];
page.on('pageerror', error => errors.push(error.message));
page.on('request', request => {
  if (request.url().includes('/EXCHANGE_MATCH_PIXEL_BATCH')) {
    exchangeRequests.set(request, performance.now());
  }
});
page.on('response', response => {
  if (response.url().includes('/doom_api/') && response.status() >= 400) {
    void response.text().then(body=>{
      apiFailures.push(`${response.status()} ${response.url()} `
        +body.slice(0,2_000));
    }).catch(()=>{
      apiFailures.push(`${response.status()} ${response.url()}`);
    });
  }
  const started=exchangeRequests.get(response.request());
  if(started!==undefined) {
    exchangeResults.push({
      outcome:`HTTP_${response.status()}`,
      elapsedMs:performance.now()-started
    });
    exchangeRequests.delete(response.request());
  }
});
page.on('requestfailed', request => {
  const started=exchangeRequests.get(request);
  if(started!==undefined) {
    exchangeResults.push({
      outcome:request.failure()?.errorText??'FAILED',
      elapsedMs:performance.now()-started
    });
    exchangeRequests.delete(request);
  }
});
await page.addInitScript(() => {
  window.__doomPresented = [];
  window.__doomPixelTrace = {
    present: [], batch: [], starvation: [], resync: [], input: [], effective: [],
    confirmedDrop: [], inputCatchup: []
  };
  window.__doomPreviousIndices = null;
  const fingerprint = bytes => {
    let hash = 0x811c9dc5;
    for (let index = 0; index < bytes.length; index += 1) {
      hash = Math.imul(hash ^ bytes[index], 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  };
  window.addEventListener('doom:multiplayer-present', event => {
    window.__doomPresented.push(event.detail.at);
    const indices = event.detail.frameIndices;
    let changedPixels = null;
    if (indices instanceof Uint8Array) {
      if (window.__doomPreviousIndices instanceof Uint8Array) {
        changedPixels = 0;
        for (let index=0;index<indices.length;index+=1) {
          if(indices[index]!==window.__doomPreviousIndices[index])
            changedPixels+=1;
        }
      }
      window.__doomPreviousIndices=Uint8Array.from(indices);
    }
    const canvas = document.querySelector('canvas');
    const canvasBytes = canvas?.getContext('2d')
      ?.getImageData(0, 0, 320, 200).data;
    window.__doomPixelTrace.present.push({
      ...event.detail,
      frameIndices: undefined,
      databaseFingerprint: indices instanceof Uint8Array
        ? fingerprint(indices) : null,
      changedPixels,
      canvasFingerprint: canvasBytes instanceof Uint8ClampedArray
        ? fingerprint(canvasBytes) : null,
    });
  });
  window.addEventListener('doom:multiplayer-pixel-batch', event => {
    window.__doomPixelTrace.batch.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-pixel-starvation', event => {
    window.__doomPixelTrace.starvation.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-pixel-resync', event => {
    window.__doomPixelTrace.resync.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-input', event => {
    window.__doomPixelTrace.input.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-input-effective', event => {
    window.__doomPixelTrace.effective.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-pixel-confirmed-drop', event => {
    window.__doomPixelTrace.confirmedDrop.push(event.detail);
  });
  window.addEventListener('doom:multiplayer-pixel-input-catchup', event => {
    window.__doomPixelTrace.inputCatchup.push(event.detail);
  });
});
await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60_000});
await page.waitForFunction(
  () => document.body.textContent.includes('press Enter to start'),
  null, {timeout: 60_000});
await page.keyboard.press('Enter');
await page.waitForFunction(
  () => document.body.textContent.includes('MAIN MENU'),
  null, {timeout: 30_000});
await page.keyboard.press('Enter');
await page.waitForFunction(
  () => document.body.textContent.includes('Choose a skill level'),
  null, {timeout: 30_000});
await page.keyboard.press('Enter');
try {
  await page.waitForFunction(
    () => window.__doomPresented.length >= 10,
    null, {timeout: 180_000});
} catch (failure) {
  const diagnostic = await page.evaluate(() => ({
    presented: window.__doomPresented.length,
    body: document.body.textContent.slice(-2000),
  }));
  console.error(
    `PMLE_PUBLIC_EXACT_STARTUP|FAIL|presented=${diagnostic.presented}`
      + `|api_failures=${JSON.stringify(apiFailures)}`
      + `|page_errors=${JSON.stringify(errors)}`
      + `|body=${JSON.stringify(diagnostic.body)}`,
  );
  throw failure;
}
await page.waitForTimeout(2_000);

const startIndex = await page.evaluate(() => window.__doomPresented.length);
if(captureDir!==undefined) {
  await page.locator('canvas').screenshot({path:`${captureDir}/00-start.png`});
}
await page.keyboard.down('ArrowUp');
const deadline = Date.now() + seconds * 1000;
const routeStarted = Date.now();
let nextFire = Date.now();
let turningLeft = false;
let turningRight = false;
let capturedAfterLeft=false;
let capturedAfterRight=false;
while (Date.now() < deadline) {
  const routeElapsed = Date.now() - routeStarted;
  if (turnDuringRoute && routeElapsed >= 1_000 && routeElapsed < 1_700
      && !turningLeft) {
    turningLeft = true;
    await page.keyboard.down('ArrowLeft');
  } else if (turningLeft && routeElapsed >= 1_700) {
    turningLeft = false;
    await page.keyboard.up('ArrowLeft');
  }
  if (turnDuringRoute && routeElapsed >= 4_000 && routeElapsed < 4_700
      && !turningRight) {
    turningRight = true;
    await page.keyboard.down('ArrowRight');
  } else if (turningRight && routeElapsed >= 4_700) {
    turningRight = false;
    await page.keyboard.up('ArrowRight');
  }
  if (fireDuringRoute && Date.now() >= nextFire) {
    await page.keyboard.down('KeyF');
    await page.waitForTimeout(120);
    await page.keyboard.up('KeyF');
    nextFire += 700;
  }
  if(captureDir!==undefined&&!capturedAfterLeft&&routeElapsed>=2_000) {
    capturedAfterLeft=true;
    await page.locator('canvas').screenshot(
      {path:`${captureDir}/01-after-left.png`});
  }
  if(captureDir!==undefined&&!capturedAfterRight&&routeElapsed>=5_500) {
    capturedAfterRight=true;
    await page.locator('canvas').screenshot(
      {path:`${captureDir}/02-after-right.png`});
  }
  await page.waitForTimeout(30);
}
if(turningLeft)await page.keyboard.up('ArrowLeft');
if(turningRight)await page.keyboard.up('ArrowRight');
await page.keyboard.up('ArrowUp');
if(captureDir!==undefined) {
  await page.locator('canvas').screenshot({path:`${captureDir}/03-end.png`});
}
const result = await page.evaluate(start => {
  const values = window.__doomPresented.slice(start);
  const gaps = values.slice(1).map((value, index) => value - values[index])
    .sort((a, b) => a - b);
  const percentile = fraction => gaps.length === 0 ? 0
    : gaps[Math.min(gaps.length - 1, Math.ceil(gaps.length * fraction) - 1)];
  const elapsed = values.length > 1 ? values.at(-1) - values[0] : 0;
  const maximumGapIndex=gaps.length===0?-1:
    values.slice(1).map((value,index)=>value-values[index])
      .findIndex(value=>value===gaps.at(-1));
  return {
    frames: values.length,
    elapsed,
    fps: elapsed > 0 ? (values.length - 1) * 1000 / elapsed : 0,
    p50: percentile(.5),
    p95: percentile(.95),
    maximum: gaps.length === 0 ? 0 : gaps.at(-1),
    maximumGapTic:maximumGapIndex<0?null:
      window.__doomPixelTrace.present.slice(start)[maximumGapIndex+1]?.tic??null,
    match:localStorage.getItem('doomdb.solo.current'),
    trace: window.__doomPixelTrace,
    hud: document.body.textContent,
  };
}, startIndex);
if(captureDir!==undefined) {
  writeFileSync(`${captureDir}/trace.json`,`${JSON.stringify({
    injectedRttMs,result,exchangeResults,apiFailures,errors
  })}\n`);
}
if (errors.length !== 0) {
  throw new Error(`public exact-frame browser errors: ${errors.join(' | ')}`);
}
console.log(`PMLE_PUBLIC_MATCH|id=${result.match??'UNKNOWN'}`);
console.log(
  `PMLE_PUBLIC_EXACT_FPS|PASS|seconds=${seconds}|frames=${result.frames}`
    + `|injected_rtt_ms=${injectedRttMs}`
    + `|elapsed_ms=${result.elapsed.toFixed(3)}`
    + `|fps=${result.fps.toFixed(3)}`
    + `|gap_p50_ms=${result.p50.toFixed(3)}`
    + `|gap_p95_ms=${result.p95.toFixed(3)}`
    + `|gap_max_ms=${result.maximum.toFixed(3)}`
    + `|gap_max_tic=${result.maximumGapTic??-1}`
    + `|starvations=${result.trace.starvation.length}`,
);
const scoredTrace = result.trace.present.filter(
  entry => entry.at >= result.trace.present.at(-result.frames)?.at);
const databaseFingerprints = scoredTrace
  .map(entry => entry.databaseFingerprint).filter(Boolean);
const canvasFingerprints = scoredTrace
  .map(entry => entry.canvasFingerprint).filter(Boolean);
const changedPixels = scoredTrace.map(entry=>entry.changedPixels)
  .filter(Number.isFinite).sort((left,right)=>left-right);
const consecutiveChanges = values => values.slice(1)
  .filter((value,index) => value !== values[index]).length;
const buffered = scoredTrace.map(entry => entry.bufferedFrames)
  .filter(Number.isFinite).sort((left, right) => left - right);
const batchCounts=result.trace.batch.map(entry=>entry.frameCount)
  .filter(Number.isFinite).sort((left,right)=>left-right);
const modeCounts = Object.fromEntries(
  ['ACCELERATE','FREE','DECELERATE'].map(mode => [
    mode, scoredTrace.filter(entry => entry.playoutMode === mode).length,
  ]));
const percentile = (values, fraction) => values.length === 0 ? 0
  : values[Math.min(values.length - 1, Math.ceil(values.length * fraction) - 1)];
console.log(
  `PMLE_PUBLIC_EXACT_PLAYOUT|PASS|present=${scoredTrace.length}`
    + `|buffer_min=${buffered[0] ?? 0}`
    + `|buffer_p50=${percentile(buffered,.5)}`
    + `|buffer_p95=${percentile(buffered,.95)}`
    + `|mode_accelerate=${modeCounts.ACCELERATE}`
    + `|mode_free=${modeCounts.FREE}`
    + `|mode_decelerate=${modeCounts.DECELERATE}`
    + `|batches=${result.trace.batch.length}`
    + `|batch_zero=${batchCounts.filter(value=>value===0).length}`
    + `|batch_count_p50=${percentile(batchCounts,.5)}`
    + `|batch_count_p95=${percentile(batchCounts,.95)}`
    + `|starvations=${result.trace.starvation.length}`,
);
console.log(
  `PMLE_PUBLIC_EXACT_PIXELS|${
    databaseFingerprints.length===scoredTrace.length
      &&canvasFingerprints.length===scoredTrace.length?'PASS':'FAIL'}`
    + `|present=${scoredTrace.length}`
    + `|database_unique=${new Set(databaseFingerprints).size}`
    + `|database_consecutive_changes=${consecutiveChanges(databaseFingerprints)}`
    + `|canvas_unique=${new Set(canvasFingerprints).size}`
    + `|canvas_consecutive_changes=${consecutiveChanges(canvasFingerprints)}`
    + `|changed_pixels_p50=${percentile(changedPixels,.5)}`
    + `|changed_pixels_p95=${percentile(changedPixels,.95)}`
    + `|material_frames=${changedPixels.filter(value=>value>=1_000).length}`
    + `|arrow_up_inputs=${result.trace.input.filter(
      entry=>entry.command?.forward===1).length}`
    + `|arrow_up_effective=${result.trace.effective.filter(
      entry=>entry.command?.forward===1).length}`,
);
const exchangeElapsed=exchangeResults.map(result=>result.elapsedMs)
  .sort((left,right)=>left-right);
console.log(
  `PMLE_PUBLIC_EXCHANGE|PASS|requests=${exchangeResults.length}`
    + `|http_200=${exchangeResults.filter(
      result=>result.outcome==='HTTP_200').length}`
    + `|cancelled=${exchangeResults.filter(
      result=>/abort|cancel/i.test(result.outcome)).length}`
    + `|failed=${exchangeResults.filter(
      result=>result.outcome!=='HTTP_200'
        &&!/abort|cancel/i.test(result.outcome)).length}`
    + `|elapsed_p50_ms=${percentile(exchangeElapsed,.5).toFixed(3)}`
    + `|elapsed_p95_ms=${percentile(exchangeElapsed,.95).toFixed(3)}`,
);
for(const failure of apiFailures) {
  console.log(`PMLE_PUBLIC_API_FAILURE|${JSON.stringify(failure)}`);
}
const forwardInput=result.trace.input.find(
  entry=>entry.command?.forward===1);
const forwardEffective=forwardInput===undefined?undefined:
  result.trace.effective.find(entry=>
    entry.inputSequence===forwardInput.inputSequence);
const effectivePaint=forwardEffective===undefined?undefined:
  result.trace.present.find(entry=>entry.tic>=forwardEffective.effectiveTic);
const inputToPaintMs=forwardInput===undefined||effectivePaint===undefined
  ? Number.POSITIVE_INFINITY : effectivePaint.at-forwardInput.at;
const effectiveToPaintMs=forwardEffective===undefined||effectivePaint===undefined
  ? Number.POSITIVE_INFINITY : effectivePaint.at-forwardEffective.at;
const inputDrops=forwardEffective===undefined?[]:
  result.trace.confirmedDrop.filter(entry=>
    entry.inputSequence===forwardEffective.inputSequence);
console.log(
  `PMLE_PUBLIC_INPUT_MOTION|${
    Number.isFinite(inputToPaintMs)&&inputToPaintMs<=350
      &&(effectivePaint?.changedPixels??0)>=1_000?'PASS':'FAIL'}`
    + `|input_sequence=${forwardInput?.inputSequence??-1}`
    + `|effective_tic=${forwardEffective?.effectiveTic??-1}`
    + `|paint_tic=${effectivePaint?.tic??-1}`
    + `|confirmed_frames_skipped=${inputDrops.length}`
    + `|input_to_paint_ms=${inputToPaintMs.toFixed(3)}`
    + `|effective_to_paint_ms=${effectiveToPaintMs.toFixed(3)}`
    + `|changed_pixels=${effectivePaint?.changedPixels??-1}`,
);
assert.ok(result.fps>=30,
  `database-frame canvas cadence ${result.fps.toFixed(3)} FPS`);
assert.equal(databaseFingerprints.length,scoredTrace.length,
  'database framebuffer fingerprint coverage changed');
assert.equal(canvasFingerprints.length,scoredTrace.length,
  'canvas fingerprint coverage changed');
assert.ok(consecutiveChanges(databaseFingerprints)>=
    Math.floor((databaseFingerprints.length-1)*.80),
  'held-arrow route did not produce enough distinct database frames');
assert.ok(consecutiveChanges(canvasFingerprints)>=
    Math.floor((canvasFingerprints.length-1)*.80),
  'held-arrow route did not paint enough distinct canvas buffers');
assert.ok(changedPixels.filter(value=>value>=1_000).length>=
    Math.floor(changedPixels.length*.75),
  'held-arrow route did not produce material visual motion');
assert.ok(result.trace.input.some(entry=>entry.command?.forward===1),
  'ArrowUp did not enter the browser command register');
assert.ok(result.trace.effective.some(entry=>entry.command?.forward===1),
  'ArrowUp did not reach an effective authoritative input revision');
assert.ok(inputToPaintMs<=350,
  `effective ArrowUp frame reached canvas after ${inputToPaintMs.toFixed(3)} ms`);
assert.ok((effectivePaint?.changedPixels??0)>=1_000,
  'effective ArrowUp frame did not produce material canvas motion');
if (holdSeconds > 0) {
  await page.waitForTimeout(holdSeconds * 1000);
}
await browser.close();
