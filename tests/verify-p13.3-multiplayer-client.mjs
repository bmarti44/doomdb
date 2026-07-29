import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {chromium} from 'playwright';

const nextDatabaseFrameTic=tic=>{
  assert.ok(Number.isSafeInteger(tic)&&tic>=-1);
  return tic+1;
};

const base = process.env.DOOMDB_PLAY_BASE_URL ?? 'http://localhost:8080';
const multiplayerUrl = process.env.DOOMDB_MULTIPLAYER_URL ??
  `${base}/play/multiplayer`;
const performanceFrames = Number(process.env.DOOMDB_MULTIPLAYER_FRAMES ?? 0);
const performanceStartTic =
  Number(process.env.DOOMDB_MULTIPLAYER_SCORE_START_TIC ?? 0);
const enforcePerformance = process.env.DOOMDB_PERF_DIAGNOSTIC !== '1';
const requireDatabasePixels =
  process.env.DOOMDB_REQUIRE_DATABASE_PIXELS === '1';
const multiplayerEvidencePath =
  process.env.DOOMDB_MULTIPLAYER_EVIDENCE_PATH ?? '';
const expectedArtifact={
  authoritySha256:process.env.DOOMDB_EXPECTED_AUTHORITY_SHA256??'',
  rendererSha256:process.env.DOOMDB_EXPECTED_RENDERER_SHA256??'',
  coordinatorSha256:process.env.DOOMDB_EXPECTED_COORDINATOR_SHA256??''
};
if(multiplayerEvidencePath!==''&&fs.existsSync(multiplayerEvidencePath))
  throw new Error(`refusing to overwrite multiplayer evidence: ${
    multiplayerEvidencePath}`);
assert.ok(Number.isInteger(performanceFrames) && performanceFrames >= 0 &&
  performanceFrames <= 300);
assert.ok(Number.isInteger(performanceStartTic) &&
  performanceStartTic >= 0 && performanceStartTic <= 100000);
// Two players are two devices. Sharing one Chromium process creates a local
// renderer-scheduling bottleneck that is absent from the qualified topology
// and was already eliminated from the retained-session soak harness.
const browsers = await Promise.all([0,1].map(() =>
  chromium.launch({headless:true})));
const hostContext = await browsers[0].newContext(
  {viewport:{width:1000,height:760}});
const guestContext = await browsers[1].newContext(
  {viewport:{width:1000,height:760}});
for (const context of [hostContext, guestContext]) {
  await context.addInitScript(() => {
    performance.setResourceTimingBufferSize(2000);
    window.__doomMultiplayerTrace = [];
    window.__doomMultiplayerPending = [];
    window.__doomMultiplayerCaptureFrames = false;
    for (const name of ['input', 'input-effective', 'submit', 'poll', 'ready',
      'decoded', 'present', 'pixel-confirmed-drop','pixel-batch',
      'pixel-resync','pixel-starvation']) {
      addEventListener(`doom:multiplayer-${name}`, event => {
        const row={name,...event.detail};
        window.__doomMultiplayerTrace.push(row);
        if(name!=='present')return;
        if(!(row.frameIndices instanceof Uint8Array)
            ||row.frameIndices.byteLength!==64_000)return;
        const indices=row.frameIndices;
        // Digest the database framebuffer but never retain 64 KiB per
        // pre-score presentation. Long checkpoint-alignment waits otherwise
        // grow each browser by ~100 MiB and manufacture a GC/timeout failure
        // that the production client cannot exhibit.
        delete row.frameIndices;
        if(!window.__doomMultiplayerCaptureFrames)return;
        window.__doomMultiplayerPending.push(
          crypto.subtle.digest('SHA-256',indices).then(digest=>{
            row.frameSha256=[...new Uint8Array(digest)]
              .map(byte=>byte.toString(16).padStart(2,'0')).join('');
          }));
      });
    }
    addEventListener('doom:api-retry',event => {
      window.__doomMultiplayerTrace.push({name:'api-retry',...event.detail});
    });
  });
}
const host = await hostContext.newPage();
const guest = await guestContext.newPage();
let match = '';
const releaseBrowserMatch=async page=>{
  if(!/^[0-9a-f]{32}$/.test(match)||page.isClosed())return;
  await page.evaluate(async matchId=>{
    const key=`doomdb.match.${matchId}`;
    const raw=sessionStorage.getItem(key)??localStorage.getItem(key);
    if(raw===null)return;
    const credentials=JSON.parse(raw);
    await fetch('/ords/doom/doom_api/LEAVE_MATCH',{
      method:'POST',headers:{
        'content-type':'application/json','accept':'application/json'
      },
      body:JSON.stringify({
        p_match:matchId,p_player_capability:credentials.playerCapability
      })
    });
    sessionStorage.removeItem(key);localStorage.removeItem(key);
  },match);
};
try {
  await host.goto(multiplayerUrl, {waitUntil: 'networkidle'});
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
    host.waitForFunction(() => /(?:DB FRAME|TIC) [1-9][0-9]*/.test(
      document.querySelector('[data-hud]')?.textContent ?? ''),
    null,{timeout:30000}),
    guest.waitForFunction(() => /(?:DB FRAME|TIC) [1-9][0-9]*/.test(
      document.querySelector('[data-hud]')?.textContent ?? ''),
    null,{timeout:30000})
  ]);
  if (process.env.DOOMDB_TEST_ORDS_RESTART === '1') {
    const beforeRestart = await Promise.all([host, guest].map(async page =>
      Number((await page.locator('[data-hud]').textContent() ?? '')
        .match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0)));
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
        const tic = Number(hud?.textContent
          ?.match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0);
        return !hud?.classList.contains('error') && tic > previous;
      }, beforeRestart[index], {timeout: 60000})));
  }
  // Browser refresh/close is an explicit leave boundary in the production
  // contract. Do not reload a live participant here: stale-slot reclamation
  // owns that scenario, while this gate keeps both POVs connected.
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
    const hostFrontier = Number((hostHud ?? '')
      .match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0);
    const guestFrontier = Number((guestHud ?? '')
      .match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0);
    if (hostFrontier >= 1 && guestFrontier >= 1 &&
        Math.abs(hostFrontier - guestFrontier) <= 4) break;
    await host.waitForTimeout(100);
  }
  assert.match(hostHud ?? '', /PLAYER 1/);
  assert.match(guestHud ?? '', /PLAYER 2/);
  const hostTic = Number((hostHud ?? '')
    .match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0);
  const guestTic = Number((guestHud ?? '')
    .match(/(?:DB FRAME|TIC) (\d+)/)?.[1] ?? 0);
  assert.ok(hostTic >= 1 && guestTic >= 1);
  assert.ok(Math.abs(hostTic - guestTic) <= 4,
    `browser frontiers diverged host=${hostTic} guest=${guestTic}`);
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
    const text=document.querySelector('[data-hud]')?.textContent ?? '';
    if(/DB FRAME [1-9][0-9]*/.test(text))return true;
    const lag=Number(text
      ?.match(/LAG (\d+)/)?.[1] ?? 999);
    return lag<=4;
  },null,{timeout:30000})));
  let performanceSummary = '';
  if (performanceFrames > 0) {
    // The unique-moving-frame contract requires continuous visual motion for
    // the entire scored window. Inputs are scheduled ahead of the confirmed
    // frontier, so keydown is not the beginning of authoritative movement.
    // Wait until each moving command is effective before taking the scored
    // start marker; otherwise the lead window is an idle-scene fixture bug.
    await Promise.all([
      host.keyboard.down('w'),host.keyboard.down('ArrowRight'),
      guest.keyboard.down('w'),guest.keyboard.down('ArrowLeft')
    ]);
    try {
      await Promise.all([host,guest].map((page,index)=>page.waitForFunction(
        expectedTurn=>{
          const effective=[...window.__doomMultiplayerTrace].reverse().find(row=>
            row.name==='input-effective'&&row.command?.forward===1
              &&row.command?.turn===expectedTurn);
          const presented=[...window.__doomMultiplayerTrace].reverse()
            .find(row=>row.name==='present');
          return effective!==undefined&&presented!==undefined
            &&presented.tic>=effective.effectiveTic;
        },
        index===0?1:-1,{timeout:30000})));
    } catch(cause) {
      const diagnostic=await Promise.all([host,guest].map(page=>
        page.evaluate(()=>({
          hud:document.querySelector('[data-hud]')?.textContent??'',
          trace:[...window.__doomMultiplayerTrace].slice(-20)
        }))));
      throw new Error(
        `moving-input presentation did not converge ${JSON.stringify(
          diagnostic)}`,{cause});
    }
    if(performanceStartTic>0) {
      await Promise.all([host,guest].map(page=>page.waitForFunction(
        minimumTic=>{
          const presented=[...window.__doomMultiplayerTrace].reverse()
            .find(row=>row.name==='present');
          return presented!==undefined&&presented.tic>=minimumTic;
        },performanceStartTic,{timeout:120000})));
    }
    await Promise.all([host,guest].map(page=>page.evaluate(()=>{
      window.__doomMultiplayerCaptureFrames=true;
    })));
    const starts = await Promise.all([host, guest].map(page => page.evaluate(() => ({
      count: window.__doomMultiplayerTrace.filter(row => row.name === 'present').length,
      at: performance.now()
    }))));
    let exerciseFire = true;
    const fireExercise = (async () => {
      // Produce real command transitions throughout the scored interval so
      // input-to-effect measures actions, not periodic identical keepalives.
      // Skill-3 co-op players can die during this moving/firing fixture.
      // Periodically hold Use across a poll interval so dead players respawn;
      // otherwise a legitimate static death view invalidates the intended
      // unique-moving-frame workload rather than the renderer.
      for (let sample = 0; sample < 20 && exerciseFire; sample += 1) {
        if ((sample & 1) === 0) {
          await Promise.all([
            host.keyboard.down('ControlLeft'),
            guest.keyboard.down('ControlLeft')
          ]);
        } else {
          await Promise.all([
            host.keyboard.up('ControlLeft'),
            guest.keyboard.up('ControlLeft')
          ]);
        }
        if(sample%4===0) {
          await Promise.all([
            host.keyboard.down('Space'),guest.keyboard.down('Space')
          ]);
          await host.waitForTimeout(100);
          await Promise.all([
            host.keyboard.up('Space'),guest.keyboard.up('Space')
          ]);
          await host.waitForTimeout(125);
        } else {
          await host.waitForTimeout(225);
        }
      }
    })();
    try {
      await Promise.all([
        ...[host, guest].map((page, index) => page.waitForFunction(
          ({start, count}) => window.__doomMultiplayerTrace
            .filter(row => row.name === 'present').length >= start + count,
          {start: starts[index].count, count: performanceFrames}, {timeout: 120000}))
      ]);
    } catch (cause) {
      const diagnostic = await Promise.all([host, guest].map(page => page.evaluate(() => {
        const presents = window.__doomMultiplayerTrace.filter(row => row.name === 'present');
        const resources=performance.getEntriesByType('resource')
          .filter(row=>row.name.includes('/ords/doom/doom_api/'))
          .slice(-20).map(row=>({
            name:new URL(row.name).pathname.split('/').at(-1),
            duration:row.duration,
            ttfb:row.responseStart-row.requestStart,
            download:row.responseEnd-row.responseStart
          }));
        return {hud: document.querySelector('[data-hud]')?.textContent ?? '',
          totalPresents: presents.length,lastTic:presents.at(-1)?.tic??null,
          recentTrace:[...window.__doomMultiplayerTrace].slice(-30),
          resources};
      })));
      throw new Error(`multiplayer performance timeout ${JSON.stringify(diagnostic)}`,
        {cause});
    } finally {
      exerciseFire = false;
      await fireExercise;
      await Promise.all([
        host.keyboard.up('w'),host.keyboard.up('ArrowRight'),
        guest.keyboard.up('w'),guest.keyboard.up('ArrowLeft')
      ]);
    }
    const traces = await Promise.all([host, guest].map((page, index) =>
      page.evaluate(async ({start, count}) => {
        await Promise.all(window.__doomMultiplayerPending);
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
    if(multiplayerEvidencePath!=='') {
      const evidence={
        schema:1,
        classification:'RAW_TWO_POV_BROWSER_SAMPLES',
        requiredRenderer:requireDatabasePixels
          ?'DATABASE_PIXELS':'COMPATIBLE',
        artifact:expectedArtifact,
        framesPerPlayer:performanceFrames,
        players:traces.map(({presents,resources},slot)=>({
          slot,
          presents:presents.map(row=>({
            tic:row.tic,at:row.at,frameSha256:row.frameSha256,
            source:row.source,bufferedFrames:row.bufferedFrames,
            selectedDepth:row.selectedDepth,
            expectedBatchTics:row.expectedBatchTics,
            playoutMode:row.playoutMode
          })),
          controls:traces[slot].all
            .filter(row=>row.name==='input'||row.name==='input-effective')
            .map(row=>({
              name:row.name,at:row.at,inputSequence:row.inputSequence,
              effectiveTic:row.effectiveTic,command:row.command
            })),
          confirmedDrops:traces[slot].all
            .filter(row=>row.name==='pixel-confirmed-drop')
            .map(row=>({tic:row.tic,reason:row.reason})),
          resources
        }))
      };
      fs.writeFileSync(multiplayerEvidencePath,
        `${JSON.stringify(evidence)}\n`,{encoding:'utf8',mode:0o600,flag:'wx'});
    }
    const guestFramesByTic=new Map(
      traces[1].presents.map(frame=>[frame.tic,frame.frameSha256]));
    const commonPovFrames=traces[0].presents
      .filter(frame=>guestFramesByTic.has(frame.tic));
    assert.ok(commonPovFrames.length>=250,
      `two-POV overlap is too small: ${commonPovFrames.length}`);
    assert.ok(commonPovFrames.every(frame=>
      frame.frameSha256!==guestFramesByTic.get(frame.tic)),
    'measured player POV framebuffers collapsed');
    const percentile = (values, fraction) => {
      if (values.length === 0) return 0;
      const ordered = [...values].sort((a, b) => a - b);
      return ordered[Math.ceil(ordered.length * fraction) - 1];
    };
    const summaries = traces.map(({all, presents, resources}, slot) => {
      assert.equal(presents.length, performanceFrames);
      assert.equal(new Set(presents.map(row => row.tic)).size,
        performanceFrames, `player ${slot} repeated a measured tic`);
      assert.equal(new Set(presents.map(row=>row.frameSha256)).size,
        performanceFrames,`player ${slot} repeated a measured framebuffer`);
      if(requireDatabasePixels) {
        assert.ok(presents.every(row=>row.source==='database-framebuffer'),
          `player ${slot} observed a non-database framebuffer`);
      }
      const confirmedDropTics=new Set(all
        .filter(row=>row.name==='pixel-confirmed-drop')
        .map(row=>row.tic));
      let confirmedDropCount=0;
      for (let index = 1; index < presents.length; index += 1) {
        let expected=nextDatabaseFrameTic(presents[index-1].tic);
        let boundedDrops=0;
        while(expected<presents[index].tic) {
          assert.ok(confirmedDropTics.has(expected),
            `player ${slot} unaccounted confirmed frame skip ${expected}`);
          confirmedDropCount+=1;
          boundedDrops+=1;
          assert.ok(boundedDrops<=4,
            `player ${slot} confirmed input drop burst exceeded four frames`);
          expected=nextDatabaseFrameTic(expected);
        }
        assert.equal(expected,presents[index].tic,
          `player ${slot} authoritative presentation schedule changed`);
      }
      assert.ok(confirmedDropCount<=60,
        `player ${slot} excessive confirmed frame drops ${confirmedDropCount}`);
      const measuredTics = new Set(presents.map(row => row.tic));
      const firstMeasuredTic=presents[0].tic;
      const lastMeasuredTic=presents.at(-1).tic;
      const decodedTics = [...new Set(all.filter(row => row.name === 'decoded' &&
        row.tic>=presents[0].tic&&row.tic<=presents.at(-1).tic)
        .map(row => row.tic))].sort((a, b) => a - b);
      for (let index = 1; index < decodedTics.length; index += 1)
        assert.equal(decodedTics[index]-decodedTics[index-1],1,
          `player ${slot} authoritative 35 FPS schedule changed at tic ${
            decodedTics[index-1]}`);
      const gaps = presents.slice(1).map((row, index) => row.at - presents[index].at);
      const elapsed = presents.at(-1).at - presents[0].at;
      const fps = (presents.length - 1) * 1000 / elapsed;
      const inputs = all.filter(row => row.name === 'input' && row.at>=starts[slot].at);
      const changedInputSequences=new Set();
      let priorCommand='';
      for(const input of inputs) {
        const command=JSON.stringify(input.command);
        if(command!==priorCommand)changedInputSequences.add(input.inputSequence);
        priorCommand=command;
      }
      const applicable = new Map();
      // Input latency is measured against the first exact confirmed
      // framebuffer at or beyond the authoritative effective tic.
      for (const effective of all.filter(row => row.name === 'input-effective' &&
        row.effectiveTic>=firstMeasuredTic&&row.effectiveTic<=lastMeasuredTic
          &&changedInputSequences.has(row.inputSequence))) {
        const prior=applicable.get(effective.effectiveTic);
        if (prior===undefined || effective.inputSequence>prior.inputSequence)
          applicable.set(effective.effectiveTic,effective);
      }
      const latencies = [...applicable.values()].map(effective => {
        const input = inputs.find(row => row.inputSequence === effective.inputSequence);
        const presented = presents.find(row => row.tic >= effective.effectiveTic);
        return input === undefined || presented === undefined ? null : presented.at-input.at;
      }).filter(value => value !== null);
      assert.ok(latencies.length>=(enforcePerformance?20:0),
        `player ${slot} input overlay samples=${latencies.length}`);
      const p50 = percentile(gaps, .5), p95 = percentile(gaps, .95);
      const p99 = percentile(gaps, .99);
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
      const pollResources=resources.filter(row=>
        row.name==='poll_match_batch'||row.name==='poll_match_pixel_batch'
          ||row.name==='exchange_match_pixel_batch');
      const resourceTail=(rows,field)=>rows.length===0?0:percentile(rows.map(row=>row[field]),.95);
      const detail = `p${slot}=${fps.toFixed(2)}fps paint=${p50.toFixed(2)}/${p95.toFixed(2)}ms paint99/999/max=${p99.toFixed(2)}/${p999.toFixed(2)}/${paintMax.toFixed(2)}ms submitGap=${percentile(submitGaps, .5).toFixed(2)}/${percentile(submitGaps, .95).toFixed(2)}ms submitDecode=${percentile(server, .5).toFixed(2)}/${percentile(server, .95).toFixed(2)}ms pollReady=${percentile(delivery, .5).toFixed(2)}/${percentile(delivery, .95).toFixed(2)}ms decodePaint=${percentile(decodePaint, .5).toFixed(2)}/${percentile(decodePaint, .95).toFixed(2)}ms input=${inputP50.toFixed(2)}/${inputP95.toFixed(2)}ms input999/max=${inputP999.toFixed(2)}/${inputMax.toFixed(2)}ms n=${latencies.length} worstPaint=${worstGap.tic}:${worstGap.value.toFixed(1)} net95=submit(q${resourceTail(submitResources,'queue').toFixed(1)},t${resourceTail(submitResources,'ttfb').toFixed(1)},d${resourceTail(submitResources,'download').toFixed(1)})/poll(q${resourceTail(pollResources,'queue').toFixed(1)},t${resourceTail(pollResources,'ttfb').toFixed(1)},d${resourceTail(pollResources,'download').toFixed(1)})`;
      if (enforcePerformance) {
        assert.ok(fps >= 30, `player ${slot} ${detail}`);
        assert.ok(p50 <= 33.3 && p95 <= 33.3, `player ${slot} ${detail}`);
        assert.ok(p99<=2*1000/35&&paintMax<=100,
          `player ${slot} ${detail}`);
        assert.ok(inputP50<=250 && inputP95<=250,
          `player ${slot} ${detail}`);
      }
      return detail;
    });
    performanceSummary = ` frames=${performanceFrames} ${summaries.join(' ')}`;
  }
  process.stdout.write(
    `PASS P13.3-MULTIPLAYER-CLIENT mode=${requestedMode}`
      + ` renderer=${requireDatabasePixels?'DATABASE_PIXELS':'COMPATIBLE'}`
      + ` two browsers dynamic-input ${
        process.env.DOOMDB_TEST_ORDS_RESTART === '1' ? 'ORDS-restart ' : ''}`
      + `confirmed-only distinct-POVs hostTic=${hostTic} guestTic=${guestTic}`
      +`${performanceSummary} (bearers redacted)\n`);
} finally {
  // Guest first preserves host authority long enough to release both leases.
  for(const page of [guest,host]) {
    try {await releaseBrowserMatch(page);} catch {/* Cleanup is best effort. */}
  }
  await Promise.all(browsers.map(browser=>browser.close()));
}
