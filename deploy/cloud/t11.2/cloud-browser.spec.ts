import {test, expect} from '@playwright/test';
import type {Page} from '@playwright/test';
import crypto from 'node:crypto';
import fs from 'node:fs';

type FrameObservation = {
  at:number; tic:number; sha256:string; source:string;
  bufferedFrames:number;selectedDepth:number;expectedBatchTics:number;
  playoutMode:string
};
type BrowserGate = {
  presents: FrameObservation[];
  pending: Promise<void>[];
  diagnostics: {name:string;detail:Record<string,unknown>}[];
};

const sha = (value:string|Buffer) =>
  crypto.createHash('sha256').update(value).digest('hex');
const appUrl = new URL(process.env.T112_HOSTED_INDEX_URL!);
const output = process.env.T112_BROWSER_LEDGER!;

type CleanupCredentials={match:string;playerCapability:string};

const captureCleanupCredentials = async (page:Page) =>
  page.evaluate(():CleanupCredentials|null => {
    const match=localStorage.getItem('doomdb.solo.current');
    if (match===null) return null;
    const raw=localStorage.getItem(`doomdb.match.${match}`);
    if (raw===null) return null;
    const credentials=JSON.parse(raw) as {playerCapability?:unknown};
    return typeof credentials.playerCapability==='string'
      ? {match,playerCapability:credentials.playerCapability}
      : null;
  });

const releaseMatch = async (
    page:Page,fallback:CleanupCredentials|null=null) =>
  page.evaluate(async (captured:CleanupCredentials|null) => {
  const match=localStorage.getItem('doomdb.solo.current');
  const raw=match===null?null:localStorage.getItem(`doomdb.match.${match}`);
  const stored=raw===null?null:JSON.parse(raw) as {
    playerCapability?:unknown
  };
  const credentials=match!==null&&typeof stored?.playerCapability==='string'
    ? {match,playerCapability:stored.playerCapability}
    : captured;
  if(credentials===null)return {released:false,absent:true};
  const response=await fetch('/ords/doom/doom_api/LEAVE_MATCH',{
    method:'POST',headers:{
      'content-type':'application/json','accept':'application/json'
    },
    body:JSON.stringify({p_match:credentials.match,
      p_player_capability:credentials.playerCapability})
  });
  localStorage.removeItem('doomdb.solo.current');
  localStorage.removeItem(`doomdb.match.${credentials.match}`);
  return {released:response.ok,status:response.status,
    matchSha256:await crypto.subtle.digest('SHA-256',
      new TextEncoder().encode(credentials.match)).then(value =>
        [...new Uint8Array(value)].map(byte =>
          byte.toString(16).padStart(2,'0')).join(''))};
},fallback);

test.afterEach(async ({page}) => {
  if (!page.isClosed()) await releaseMatch(page);
});

test('[T112-LIVE-OCI-BROWSER] database-generated framebuffer client', async ({page}) => {
  expect(appUrl.protocol).toBe('https:');
  expect(appUrl.pathname).toMatch(/\/ords\/doom\/app\/$/);
  const origin = appUrl.origin;
  const errors:string[] = [];
  const network:any[] = [];
  let verifiedBlobModuleLoads = 0;
  let collecting = true;
  page.on('console', message => {
    if (collecting && message.type() === 'error')
      errors.push(`console:${message.text()}`);
  });
  page.on('pageerror', error => {
    if (collecting) errors.push(`pageerror:${error.message}`);
  });
  page.on('requestfailed', request =>
    collecting &&
      errors.push(`requestfailed:${request.failure()?.errorText ?? 'unknown'}`));
  page.on('request', request => {
    if (!collecting) return;
    const url = new URL(request.url());
    if (url.protocol==='blob:') {
      // The database-frame release must not instantiate a browser authority
      // or renderer. Retain the counter so any regression is explicit.
      verifiedBlobModuleLoads+=1;return;
    }
    network.push({
      kind: url.pathname.includes('/doom_api/') ? 'ORACLE_API'
        : url.pathname.includes('/app/') ? 'DATABASE_STATIC' : 'OTHER',
      urlSha256: sha(url.href), originSha256: sha(url.origin),
      method: request.method(), status: 0, redirected: false,
      operation: url.pathname.split('/').filter(Boolean).at(-1) ?? '',
      failed: false, websocket: request.resourceType() === 'websocket',
      mocked: false
    });
  });
  page.on('response', response => {
    if (!collecting) return;
    const row = [...network].reverse().find(item =>
      item.urlSha256 === sha(response.url()) && item.status === 0);
    if (row !== undefined) {
      row.status = response.status();
      row.redirected = response.request().redirectedFrom() !== null;
    }
  });
  await page.addInitScript(() => {
    const gate:BrowserGate = {presents: [], pending: [], diagnostics: []};
    Object.defineProperty(window, '__doomT112Gate', {value: gate});
    window.addEventListener('doom:multiplayer-present', event => {
      const detail = (event as CustomEvent).detail as {
        at:number;tic:number;source?:string;
        bufferedFrames?:number;selectedDepth?:number;
        expectedBatchTics?:number;playoutMode?:string;
        frameIndices?:Uint8Array
      };
      if(!(detail.frameIndices instanceof Uint8Array)
          ||detail.frameIndices.byteLength!==64_000)return;
      const pending = crypto.subtle.digest(
        'SHA-256',detail.frameIndices).then(value => {
        const sha256 = [...new Uint8Array(value)]
          .map(byte => byte.toString(16).padStart(2,'0')).join('');
        gate.presents.push({
          at:detail.at,tic:detail.tic,sha256,
          source:detail.source ?? 'UNDECLARED',
          bufferedFrames:Number(detail.bufferedFrames ?? -1),
          selectedDepth:Number(detail.selectedDepth ?? -1),
          expectedBatchTics:Number(detail.expectedBatchTics ?? -1),
          playoutMode:String(detail.playoutMode ?? 'UNDECLARED')
        });
      });
      gate.pending.push(pending);
    });
    for (const [eventName,name] of [
      ['doom:multiplayer-batch','batch'],
      ['doom:multiplayer-apply-batch','apply-batch'],
      ['doom:multiplayer-resync','resync'],
      ['doom:multiplayer-pixel-resync','pixel-resync'],
      ['doom:multiplayer-pixel-batch','pixel-batch'],
      ['doom:multiplayer-pixel-playout-start','pixel-playout-start'],
      ['doom:multiplayer-pixel-starvation','pixel-starvation'],
      ['doom:multiplayer-recovery-wait','recovery-wait'],
      ['doom:multiplayer-lead','lead'],
      ['doom:multiplayer-input-effective','input-effective'],
      ['doom:api-retry','api-retry']
    ]) {
      window.addEventListener(eventName,event => {
        const detail=(event as CustomEvent).detail as Record<string,unknown>;
        gate.diagnostics.push({name,detail});
        if (gate.diagnostics.length>2048) gate.diagnostics.shift();
      });
    }
  });

  // The root document and solo entry are both served from the dedicated
  // database-resident module. Opening the root first proves relative module
  // and content-addressed asset resolution before starting a capacity-bearing
  // game.
  await page.goto(appUrl.href,{waitUntil:'networkidle'});
  await expect(page.locator('canvas[data-doom-canvas]')).toHaveAttribute('width','320');
  await page.goto(new URL('./solo.html#solo=1&skill=3',appUrl).href,
    {waitUntil:'domcontentloaded'});
  const canvas = page.locator('canvas[data-doom-canvas]');
  await expect(canvas).toBeVisible({timeout:180_000});
  await page.waitForFunction(() => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    return gate.presents.length>=2;
  },undefined,{timeout:240_000});

  await canvas.focus();
  await page.keyboard.down('KeyW');
  await page.keyboard.down('ArrowRight');
  await page.waitForFunction(() => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    // T112_MOVING_INPUT_EFFECTIVE_FENCE: do not match an earlier heartbeat.
    return gate.diagnostics.some(row =>
      row.name==='input-effective' &&
      Number((row.detail.command as Record<string,unknown>|undefined)
        ?.forward)!==0 &&
      Number((row.detail.command as Record<string,unknown>|undefined)
        ?.turn)!==0);
  },undefined,{timeout:30_000});
  const effectiveTic=await page.evaluate(() => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    // T112_MOVING_INPUT_EFFECTIVE_FENCE: bind the scored window to movement.
    const row=[...gate.diagnostics].reverse().find(
      candidate=>candidate.name==='input-effective' &&
        Number((candidate.detail.command as Record<string,unknown>|undefined)
          ?.forward)!==0 &&
        Number((candidate.detail.command as Record<string,unknown>|undefined)
          ?.turn)!==0);
    return Number(row?.detail.effectiveTic);
  });
  expect(Number.isInteger(effectiveTic)).toBe(true);
  // Exclude cold engine catch-up and the scheduled input-lead window. The
  // scored period begins only after one second of confirmed moving play.
  await page.waitForFunction(target => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    return gate.presents.some(frame=>frame.tic>=Number(target)+32);
  },effectiveTic,{timeout:30_000});
  await page.evaluate(async () => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    await Promise.all(gate.pending);
    gate.presents.length=0;gate.pending.length=0;
  });
  const scoredNetworkStart=network.length;
  await page.waitForFunction(() => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    return gate.presents.length>=300;
  },undefined,{timeout:120_000});
  await page.keyboard.up('ArrowRight');
  await page.keyboard.up('KeyW');
  if (process.env.T112_SCREENSHOT_PATH)
    await page.screenshot({
      path:process.env.T112_SCREENSHOT_PATH,fullPage:true
    });
  collecting=false;
  // Capture the authenticated identity before pagehide deliberately erases
  // browser storage. The subsequent explicit LEAVE is an idempotency proof for
  // the beacon path and preserves the match SHA needed by runtime postflight.
  const cleanupCredentials=await captureCleanupCredentials(page);
  expect(cleanupCredentials).not.toBeNull();
  await page.evaluate(() =>
    window.dispatchEvent(new PageTransitionEvent('pagehide')));
  await page.waitForTimeout(50);
  for (let index=network.length-1;index>=0;index-=1)
    if (network[index]!.status===0) network.splice(index,1);
  const observed = await page.evaluate(async () => {
    const gate=(window as any).__doomT112Gate as BrowserGate;
    await Promise.all(gate.pending);
    return {frames:gate.presents.sort((a,b)=>a.at-b.at).slice(-300),
      diagnostics:gate.diagnostics};
  });
  const {frames,diagnostics}=observed;
  expect(frames).toHaveLength(300);
  const intervals=frames.slice(1).map((frame,index)=>frame.at-frames[index]!.at)
    .sort((a,b)=>a-b);
  const p95=intervals[Math.ceil(intervals.length*.95)-1]!;
  const p99=intervals[Math.ceil(intervals.length*.99)-1]!;
  const maximumInterval=intervals.at(-1)!;
  const percentile=(fraction:number):number =>
    intervals[Math.max(0,Math.ceil(intervals.length*fraction)-1)]!;
  const elapsed=frames.at(-1)!.at-frames[0]!.at;
  const fps=(frames.length-1)*1000/elapsed;
  const uniqueFrames=new Set(frames.map(frame=>frame.sha256)).size;
  let confirmedDropCount=0;
  const sequentialTics=frames.every((frame,index) => {
    if(index===0)return true;
    const delta=frame.tic-frames[index-1]!.tic;
    const scheduledSourceOmission=
      delta===2&&(frames[index-1]!.tic+1)%20===0;
    if(delta!==1&&!scheduledSourceOmission)confirmedDropCount+=delta-1;
    // The source schedule omits every twentieth tic. Client-side latency
    // control may not delete additional confirmed presentation frames.
    return delta===1||scheduledSourceOmission;
  });
  const databasePixelFrames=frames.every(frame =>
    frame.source==='database-framebuffer');
  const scoredNetwork=network.slice(scoredNetworkStart);
  const operations=scoredNetwork
    .filter(row=>row.kind==='ORACLE_API')
    .map(row=>String(row.operation).toUpperCase());
  const pixelPolls=operations.filter(operation=>
    operation==='POLL_MATCH_PIXEL_BATCH'
      ||operation==='EXCHANGE_MATCH_PIXEL_BATCH').length;
  const pixelPollsPerScoredFrame=pixelPolls/frames.length;
  const bufferedFrames=frames.map(frame=>frame.bufferedFrames)
    .sort((left,right)=>left-right);
  const selectedDepths=frames.map(frame=>frame.selectedDepth);
  const expectedBatchTics=frames.map(frame=>frame.expectedBatchTics);
  const playoutModes=frames.map(frame=>frame.playoutMode);
  const scoredStartAt=frames[0]!.at;
  const scoredDiagnostics=diagnostics.filter(row=>
    Number(row.detail.at)>=scoredStartAt);
  const pixelBatchDiagnostics=diagnostics.filter(row=>row.name==='pixel-batch');
  const playoutStarts=diagnostics.filter(
    row=>row.name==='pixel-playout-start');
  const framePercentile=(values:number[],fraction:number):number =>
    values[Math.max(0,Math.ceil(values.length*fraction)-1)]!;

  // Release capacity and retain the complete measured verdict before any
  // assertion can terminate the test. A failed performance cell must remain
  // diagnosable from its raw sample spread, not only its first assertion.
  const cleanup = await releaseMatch(page,cleanupCredentials);
  const ledger={
    schema:2,
    hostedOriginSha256:sha(origin),
    indexUrlSha256:sha(appUrl.href),
    errors,
    network,
    verifiedBlobModuleLoads,
    performance:{
      frames:frames.length,uniqueFrames,sequentialTics,
      confirmedDropCount,
      databasePixelFrames,
      fps,p50IntervalMs:percentile(.50),p90IntervalMs:percentile(.90),
      p95IntervalMs:p95,p99IntervalMs:p99,
      maxIntervalMs:maximumInterval,
      pixelPolls,pixelPollsPerScoredFrame,
      bufferOccupancyMin:bufferedFrames[0]!,
      bufferOccupancyP50:framePercentile(bufferedFrames,.50),
      bufferOccupancyP95:framePercentile(bufferedFrames,.95),
      selectedDepthMin:Math.min(...selectedDepths),
      selectedDepthMax:Math.max(...selectedDepths),
      expectedBatchTicsMin:Math.min(...expectedBatchTics),
      expectedBatchTicsMax:Math.max(...expectedBatchTics),
      playoutModeFrames:{
        accelerate:playoutModes.filter(mode=>mode==='ACCELERATE').length,
        free:playoutModes.filter(mode=>mode==='FREE').length,
        decelerate:playoutModes.filter(mode=>mode==='DECELERATE').length
      },
      scoredPixelStarvations:scoredDiagnostics.filter(
        row=>row.name==='pixel-starvation').length,
      scoredPixelResyncs:scoredDiagnostics.filter(
        row=>row.name==='pixel-resync').length,
      intervalsOver33333:intervals.filter(value=>value>33.333).length,
      duplicateFrameTics:frames.filter((frame,index) =>
        frames.findIndex(candidate=>candidate.sha256===frame.sha256)!==index)
        .map(frame=>frame.tic),
      firstTic:frames[0]!.tic,lastTic:frames.at(-1)!.tic,
      frameChainSha256:sha(frames.map(frame=>frame.sha256).join(''))
    },
    diagnostics,
    cleanup
  };
  fs.writeFileSync(output,`${JSON.stringify(ledger)}\n`,{mode:0o600});

  expect(fps).toBeGreaterThanOrEqual(30);
  expect(p95).toBeLessThanOrEqual(33.333);
  // A p95-only throughput gate can hide periodic checkpoint or scheduler
  // freezes. Keep the tail playable: no more than two native tic periods at
  // p99 and no individual presentation pause longer than 100 ms.
  expect(p99).toBeLessThanOrEqual(2*1000/35);
  expect(maximumInterval).toBeLessThanOrEqual(100);
  expect(uniqueFrames).toBe(frames.length);
  expect(sequentialTics).toBe(true);
  expect(confirmedDropCount).toBe(0);
  expect(databasePixelFrames).toBe(true);
  expect(operations).toContain('EXCHANGE_MATCH_PIXEL_BATCH');
  expect(operations).not.toContain('POLL_MATCH_TRANSITIONS');
  expect(pixelPollsPerScoredFrame).toBeLessThanOrEqual(2.5);
  expect(bufferedFrames.every(value=>Number.isInteger(value)&&value>=0))
    .toBe(true);
  // Occupancy is sampled immediately after consuming a frame, so zero is
  // permitted between that paint and an on-time response. A real underrun is
  // gated below by the deadline-aware pixel-starvation event plus p99/max.
  expect(selectedDepths.every(value=>value===6)).toBe(true);
  expect(expectedBatchTics.every(value=>
    Number.isInteger(value)&&value>=1&&value<=8)).toBe(true);
  expect(playoutModes.every(mode=>
    ['ACCELERATE','FREE','DECELERATE'].includes(mode))).toBe(true);
  expect(playoutModes.filter(mode=>mode==='FREE').length).toBeGreaterThan(0);
  expect(playoutModes.filter(mode=>mode==='ACCELERATE').length)
    .toBeLessThan(frames.length*.95);
  expect(pixelBatchDiagnostics.length).toBeGreaterThan(0);
  expect(pixelBatchDiagnostics.every(row=>
    Number.isInteger(Number(row.detail.frameCount)) &&
    Number(row.detail.frameCount)>=1 && Number(row.detail.frameCount)<=8 &&
    Number.isInteger(Number(row.detail.preClampDepth)) &&
    Number(row.detail.preClampDepth)>=1)).toBe(true);
  expect(playoutStarts.length).toBeGreaterThan(0);
  expect(playoutStarts.every(row=>
    Number(row.detail.bufferedFrames)>=
      Number(row.detail.selectedDepth)+
      Number(row.detail.expectedBatchTics))).toBe(true);
  expect(scoredDiagnostics.filter(
    row=>row.name==='pixel-starvation'||row.name==='pixel-resync')).toEqual([]);
  expect(errors).toEqual([]);
  expect(network.every(row => row.kind!=='OTHER' && row.originSha256===sha(origin)
    && !row.redirected && !row.websocket &&
    (row.status>=200 && row.status<300 ||
      row.kind==='DATABASE_STATIC' && row.status===304)))
    .toBe(true);
  expect(verifiedBlobModuleLoads).toBe(0);
  expect(cleanup.released).toBe(true);
});
