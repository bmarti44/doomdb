import assert from 'node:assert/strict';
import {execFileSync,spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import {chromium} from 'playwright';

const base=process.env.DOOMDB_PLAY_BASE_URL??'http://localhost:8080';
const seconds=Number(process.env.DOOMDB_MULTIPLAYER_SOAK_SECONDS??1800);
const warmupSeconds=Number(process.env.DOOMDB_MULTIPLAYER_SOAK_WARMUP_SECONDS??0);
const startupTimeoutMs=Number(process.env.DOOMDB_MULTIPLAYER_STARTUP_TIMEOUT_MS??300000);
const progressTimeoutMs=Number(process.env.DOOMDB_MULTIPLAYER_PROGRESS_TIMEOUT_MS??60000);
const wanGate=process.env.DOOMDB_WAN_GATE==='1';
const wanRttMs=Number(process.env.DOOMDB_WAN_RTT_MS??0);
const wanJitterMs=Number(process.env.DOOMDB_WAN_JITTER_MS??0);
const wanHoldMs=Number(process.env.DOOMDB_WAN_HOLD_MS??0);
const wanBackgroundScenario=process.env.DOOMDB_WAN_BACKGROUND_SCENARIO==='1';
const routeDiagnostics=process.env.DOOMDB_ROUTE_DIAGNOSTICS==='1';
const checkpointLivenessDiagnostic=
  process.env.DOOMDB_CHECKPOINT_LIVENESS_DIAGNOSTIC==='1';
const killCheckpointDiagnostic=
  process.env.DOOMDB_KILL_CHECKPOINT_DIAGNOSTIC==='1';
const doubleRecoveryDiagnostic=
  process.env.DOOMDB_DOUBLE_RECOVERY_DIAGNOSTIC==='1';
const highAwakeRecoveryDiagnostic=
  process.env.DOOMDB_HIGH_AWAKE_RECOVERY_DIAGNOSTIC==='1';
const highAwakeRecoveryGate=
  process.env.DOOMDB_HIGH_AWAKE_RECOVERY_GATE==='1';
const cadenceObservation=
  process.env.DOOMDB_CHECKPOINT_CADENCE_OBSERVATION==='1';
const buildHighAwakeFixture=()=>{
  const fixture=JSON.parse(fs.readFileSync(new URL(
    './fixtures/mle-live-deathmatch-2026-07-23.json',import.meta.url),'utf8'));
  assert.equal(fixture.mode,'DEATHMATCH');
  assert.equal(fixture.players,2);
  assert.equal(fixture.skill,3);
  const expandedHash=createHash('sha256');
  let expandedTics=0;
  for(const run of fixture.runs) {
    assert.match(run.command,/^[0-9a-f]{64}$/);
    for(let repeat=0;repeat<run.repeat;repeat+=1) {
      expandedHash.update(Buffer.from([run.membership]));
      expandedHash.update(Buffer.from(run.command,'hex'));
      expandedTics+=1;
    }
  }
  assert.equal(expandedTics,fixture.tics);
  assert.equal(expandedHash.digest('hex'),fixture.expandedSha256);
  const feedTics=Math.min(800,fixture.tics);
  const changes=[];
  let relativeTic=1;
  let previousVector='';
  for(const run of fixture.runs) {
    if(relativeTic>feedTics) break;
    const vector=run.command.slice(0,32).toUpperCase();
    if(vector!==previousVector) {
      changes.push({
        tic:relativeTic,p0:vector.slice(0,16),p1:vector.slice(16,32)
      });
      previousVector=vector;
    }
    relativeTic+=Math.min(run.repeat,feedTics-relativeTic+1);
  }
  return {fixture,feedTics,changes};
};
assert.ok(Number.isInteger(seconds)&&seconds>=20&&seconds<=1800);
assert.ok(Number.isInteger(warmupSeconds)&&warmupSeconds>=0&&warmupSeconds<=600);
assert.ok(Number.isInteger(startupTimeoutMs)&&startupTimeoutMs>=60000&&startupTimeoutMs<=600000);
assert.ok(Number.isInteger(progressTimeoutMs)&&progressTimeoutMs>=60000&&progressTimeoutMs<=600000);
if(wanGate) {
  assert.ok(wanRttMs>0&&wanJitterMs>=0&&wanJitterMs<=wanRttMs);
  assert.ok(wanHoldMs>=0&&wanHoldMs<=500);
  if(wanBackgroundScenario) assert.ok(warmupSeconds>=20);
}
assert.ok([
  checkpointLivenessDiagnostic,
  doubleRecoveryDiagnostic,
  highAwakeRecoveryDiagnostic,
  cadenceObservation
].filter(Boolean).length<=1,'recovery diagnostics are mutually exclusive');
if(highAwakeRecoveryDiagnostic||cadenceObservation) {
  assert.ok(routeDiagnostics,
    'checkpoint cadence scenarios require route diagnostics');
}
if(highAwakeRecoveryGate) {
  assert.ok(highAwakeRecoveryDiagnostic,
    'high-awake recovery gate requires the diagnostic scenario');
}
const matchFile=process.env.DOOMDB_MATCH_ID_FILE;
assert.ok(matchFile,'DOOMDB_MATCH_ID_FILE is required');
const dbContainer=execFileSync('docker',['compose','ps','-q','db'],{encoding:'utf8'}).trim();
assert.ok(dbContainer,'database container is unavailable');
const dbSql=sql=>execFileSync('docker',['exec','-i',dbContainer,'sqlplus','-s',
  '/','as','sysdba'],{
    input:`whenever oserror exit failure rollback\n`+
      `whenever sqlerror exit sql.sqlcode rollback\n`+
      `alter session set container=freepdb1;\n`+
      `set heading off feedback off pagesize 0\n${sql}\n`,
    encoding:'utf8'
  });
const dbSqlAsync=sql=>new Promise((resolve,reject)=>{
  const child=spawn('docker',
    ['exec','-i',dbContainer,'sqlplus','-s','/','as','sysdba'],{
      stdio:['pipe','pipe','pipe']
    });
  let stdout='';let stderr='';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data',chunk=>{stdout+=chunk;});
  child.stderr.on('data',chunk=>{stderr+=chunk;});
  child.on('error',reject);
  child.on('close',code=>{
    if(code===0) resolve(stdout);
    else reject(new Error(`async SQL*Plus exited ${code}: ${stderr||stdout}`));
  });
  child.stdin.end(`whenever oserror exit failure rollback\n`+
    `whenever sqlerror exit sql.sqlcode rollback\n`+
    `alter session set container=freepdb1;\n`+
    `set heading off feedback off pagesize 0 serveroutput on size unlimited\n`+
    `${sql}\n`);
});
const workerMemory=match=>{
  const sql=`alter session set container=freepdb1;\n`+
    `set heading off feedback off pagesize 0 linesize 32767 trimspool on\n`+
    `select 'SOAK_MEM|sessions='||(select count(*) from v$session where sid=w.worker_sid)||`+
    `'|doomSessions='||(select count(*) from v$session where username='DOOM')||`+
    `'|pga='||coalesce(max(case when n.name='session pga memory' then s.value end),0)||`+
    `'|uga='||coalesce(max(case when n.name='session uga memory' then s.value end),0)||`+
    `'|javaSession='||coalesce(max(case when n.name='java session heap live size' then s.value end),0)||`+
    `'|javaCall='||coalesce(max(case when n.name='java call heap live size' then s.value end),0)||`+
    `'|gc='||coalesce(max(case when n.name='java call heap gc count' then s.value end),0) `+
    `from doom.doom_match_worker_control w left join v$sesstat s on s.sid=w.worker_sid `+
    `left join v$statname n on n.statistic#=s.statistic# `+
    `where w.match_id='${match}' group by w.worker_sid;\n`;
  const output=execFileSync('docker',['exec','-i',dbContainer,'sqlplus','-s','/','as','sysdba'],
    {input:sql,encoding:'utf8'});
  const row=output.match(/SOAK_MEM\|sessions=(\d+)\|doomSessions=(\d+)\|pga=(\d+)\|uga=(\d+)\|javaSession=(\d+)\|javaCall=(\d+)\|gc=(\d+)/);
  assert.ok(row,'worker memory evidence missing');
  return {sessions:Number(row[1]),doomSessions:Number(row[2]),pga:Number(row[3]),
    uga:Number(row[4]),javaSession:Number(row[5]),javaCall:Number(row[6]),gc:Number(row[7])};
};
const heldPollLeases=(match,playerSlot)=>{
  const sql=`alter session set container=freepdb1;\n`+
    `set heading off feedback off pagesize 0 linesize 32767 trimspool on\n`+
    `select 'DMB1_LEASES|'||count(*) from doom.doom_match_poll_lease `+
    `where match_id='${match}' and player_slot=${playerSlot};\n`;
  const output=execFileSync('docker',['exec','-i',dbContainer,'sqlplus','-s',
    '/','as','sysdba'],{input:sql,encoding:'utf8'});
  const row=output.match(/DMB1_LEASES\|(\d+)/);
  assert.ok(row,'DMB1 lease evidence missing');
  return Number(row[1]);
};
// Both pages represent foreground clients on separate user devices. Chromium
// otherwise begins background/occluded-tab timer throttling after five minutes
// in one headless process, manufacturing an ~17 FPS tail that real foreground
// clients do not experience.
const browser=await chromium.launch({headless:true,args:[
  '--disable-background-timer-throttling',
  '--disable-backgrounding-occluded-windows',
  '--disable-renderer-backgrounding'
]});
const contexts=await Promise.all([0,1].map(()=>browser.newContext({viewport:{width:960,height:720}})));
const [host,guest]=await Promise.all(contexts.map(context=>context.newPage()));
await Promise.all([host,guest].map(page=>page.addInitScript(()=>{
  window.__doomSoakTics=[];
  window.__doomSoakPaintAt=[];
  window.__doomSoakResyncs=[];
  window.__doomWanInputs=[];
  window.__doomWanEffective=[];
  window.__doomWanConfirmed=[];
  window.__doomWanPresented=[];
  window.__doomWanBatches=[];
  window.__doomWanVisibility=[];
  window.__doomWanLead=[];
  addEventListener('doom:multiplayer-present',event=>{
    window.__doomSoakTics.push(event.detail.tic);
    window.__doomSoakPaintAt.push(performance.now());
    window.__doomWanPresented.push(event.detail);
  });
  addEventListener('doom:multiplayer-resync',event=>window.__doomSoakResyncs.push({
    atCount:window.__doomSoakTics.length,tic:event.detail.tic
  }));
  addEventListener('doom:multiplayer-input',event=>
    window.__doomWanInputs.push(event.detail));
  addEventListener('doom:multiplayer-input-effective',event=>
    window.__doomWanEffective.push(event.detail));
  addEventListener('doom:multiplayer-confirmed',event=>
    window.__doomWanConfirmed.push(event.detail));
  addEventListener('doom:multiplayer-batch',event=>
    window.__doomWanBatches.push(event.detail));
  addEventListener('doom:multiplayer-visibility',event=>
    window.__doomWanVisibility.push(event.detail));
  addEventListener('doom:multiplayer-lead',event=>
    window.__doomWanLead.push(event.detail));
})));
let match='';
let highAwakeFeed=null;
try {
  const gameUrl=new URL('/play/multiplayer',base);
  if(wanHoldMs>0) gameUrl.searchParams.set('holdMs',String(wanHoldMs));
  // This page intentionally polls Oracle. Network-idle is therefore not a
  // stable readiness contract; the create/join locators below are the actual
  // UI readiness fences.
  await host.goto(gameUrl.toString(),{waitUntil:'domcontentloaded'});
  process.stdout.write('PMLE_SOAK_STAGE|host_dom_ready\n');
  await host.locator('[data-create] input[name=name]').fill('SOAK HOST');
  process.stdout.write('PMLE_SOAK_STAGE|host_name_filled\n');
  if(highAwakeRecoveryDiagnostic) {
    await host.locator('[data-create] select[name=mode]').selectOption('DEATHMATCH');
    await host.locator('[data-create] select[name=skill]').selectOption('3');
  }
  process.stdout.write('PMLE_SOAK_STAGE|create_click_begin\n');
  await host.getByRole('button',{name:'Create two-player match'}).click();
  process.stdout.write('PMLE_SOAK_STAGE|create_clicked\n');
  await host.locator('[data-room]').waitFor({state:'visible'});
  process.stdout.write('PMLE_SOAK_STAGE|host_room_visible\n');
  const share=await host.locator('[data-share]').inputValue();
  match=new URL(share).hash.slice('#join='.length).split('.')[0]??'';
  assert.match(match,/^[0-9a-f]{32}$/);
  fs.writeFileSync(matchFile,`${match}\n`,{encoding:'ascii',mode:0o600});
  await guest.goto(share,{waitUntil:'domcontentloaded'});
  process.stdout.write('PMLE_SOAK_STAGE|guest_dom_ready\n');
  await guest.locator('[data-join] input[name=name]').fill('SOAK GUEST');
  await guest.getByRole('button',{name:'Join match'}).click();
  process.stdout.write('PMLE_SOAK_STAGE|join_clicked\n');
  await guest.locator('[data-room]').waitFor({state:'visible'});
  process.stdout.write('PMLE_SOAK_STAGE|guest_room_visible\n');
  await guest.waitForFunction(()=>location.hash.startsWith('#resume='));
  await host.waitForFunction(()=>document.querySelector('[data-room-status]')?.textContent?.includes('2/2 joined'));
  for (const page of [host,guest]) {
    await page.waitForFunction(()=>{
      const button=document.querySelector('[data-ready]');
      return button instanceof HTMLButtonElement&&!button.disabled;
    });
  }
  if(highAwakeRecoveryDiagnostic) {
    // This diagnostic deliberately disconnects the browsers after start. Give
    // both lobby members a future lease before startup so the authority's
    // comparatively slow Free-edition initialization cannot consume the
    // ordinary foreground-client liveness window first.
    const startupHold=dbSql(
      `update doom.doom_match_member set last_seen_at=`+
      `systimestamp+interval '30' minute where match_id='${match}';\n`+
      `update doom.doom_match set expires_at=`+
      `systimestamp+interval '30' minute where match_id='${match}';\n`+
      `commit;\n`+
      `select 'PMLE_HIGH_AWAKE_STARTUP_HOLD|'||count(*) `+
      `from doom.doom_match_member where match_id='${match}' `+
      `and last_seen_at>systimestamp;`);
    assert.match(startupHold,/PMLE_HIGH_AWAKE_STARTUP_HOLD\|2/,
      'high-awake diagnostic did not lease both startup members');
    const prepared=buildHighAwakeFixture();
    const lobbyOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_LOBBY_FENCE|'||match_state||'|'||`+
      `membership_epoch||'|'||generation from doom.doom_match `+
      `where match_id='${match}';`);
    const lobby=lobbyOutput.match(
      /PMLE_HIGH_AWAKE_LOBBY_FENCE\|LOBBY\|(\d+)\|(\d+)/);
    assert.ok(lobby,'high-awake lobby generation fence missing');
    const feedEpoch=Number(lobby[1]);
    const feedGeneration=Number(lobby[2])+1;
    const inserts=[];
    for(const [changeIndex,change] of prepared.changes.entries()) {
      for(const slot of [0,1]) {
        const raw=slot===0?change.p0:change.p1;
        const commandSha=createHash('sha256').update(
          Buffer.from(raw,'hex')).digest('hex');
        inserts.push(
          `insert into doom.doom_match_input_event(match_id,player_slot,`+
          `input_seq,effective_tic,membership_epoch,generation,ticcmd_raw,`+
          `command_sha,accepted_at) values('${match}',${slot},`+
          `${changeIndex+1},${change.tic},${feedEpoch},${feedGeneration},`+
          `hextoraw('${raw}'),'${commandSha}',systimestamp);`);
      }
    }
    const preloadOutput=dbSql(`${inserts.join('\n')}\ncommit;\n`+
      `select 'PMLE_HIGH_AWAKE_PRELOAD|'||count(*) from `+
      `doom.doom_match_input_event where match_id='${match}' and `+
      `generation=${feedGeneration};`);
    assert.match(preloadOutput,
      new RegExp(`^PMLE_HIGH_AWAKE_PRELOAD\\|${
        prepared.changes.length*2}$`,'m'),
      'high-awake lobby input preload did not commit');
    highAwakeFeed={...prepared,feedBase:1,feedEpoch,feedGeneration};
    process.stdout.write(`PMLE_HIGH_AWAKE_STAGE|fixture_preloaded`+
      `|tics=${prepared.feedTics}|changes=${prepared.changes.length}`+
      `|generation=${feedGeneration}\n`);
  }
  await Promise.all([host,guest].map(page=>page.locator('[data-ready]').click()));
  process.stdout.write('PMLE_SOAK_STAGE|both_ready_clicked\n');
  if(highAwakeRecoveryDiagnostic) {
    // READY_MATCH legitimately touches last_seen_at after the lobby fence
    // above. Renew immediately after both requests complete so slow retained
    // authority startup cannot age either member out.
    const readyHold=dbSql(
      `update doom.doom_match_member set last_seen_at=`+
      `systimestamp+interval '30' minute where match_id='${match}';\n`+
      `update doom.doom_match set expires_at=`+
      `systimestamp+interval '30' minute where match_id='${match}';\n`+
      `commit;\n`+
      `select 'PMLE_HIGH_AWAKE_READY_HOLD|'||count(*) `+
      `from doom.doom_match_member where match_id='${match}' `+
      `and last_seen_at>systimestamp;`);
    assert.match(readyHold,/PMLE_HIGH_AWAKE_READY_HOLD\|2/,
      'high-awake diagnostic did not lease both ready members');
  }
  if(routeDiagnostics) {
    let output='';
    for(let attempt=0;attempt<100;attempt++) {
      output=dbSql(
        `update doom.doom_match_worker_control set route_diagnostics=1,`+
        `checkpoint_test_hook=${checkpointLivenessDiagnostic?1:0} `+
        `where match_id='${match}';\ncommit;\n`+
        `select 'PMLE_ROUTE_DIAGNOSTICS|'||route_diagnostics||'|'||`+
        `checkpoint_test_hook `+
        `from doom.doom_match_worker_control where match_id='${match}';`);
      if(new RegExp(`PMLE_ROUTE_DIAGNOSTICS\\|1\\|${
        checkpointLivenessDiagnostic?1:0}`).test(output)) break;
      await host.waitForTimeout(100);
    }
    assert.match(output,new RegExp(`PMLE_ROUTE_DIAGNOSTICS\\|1\\|${
      checkpointLivenessDiagnostic?1:0}`),
      'failed to enable retained-worker stage diagnostics');
    process.stdout.write(`PMLE_ROUTE_DIAGNOSTICS|ENABLED|match=${match}\n`);
  }
  if(highAwakeRecoveryDiagnostic) {
    const startupDeadline=Date.now()+startupTimeoutMs;
    let authorityReady='';
    let lastAuthorityState='';
    while(Date.now()<startupDeadline) {
      const authorityOutput=dbSql(
        `select 'PMLE_HIGH_AWAKE_AUTHORITY_READY|'||m.match_state||'|'||`+
        `w.worker_status||'|'||m.current_tic from doom.doom_match m join `+
        `doom.doom_match_worker_control w on w.match_id=m.match_id `+
        `where m.match_id='${match}';`);
      const marker=authorityOutput.match(
        /PMLE_HIGH_AWAKE_AUTHORITY_READY\|\w+\|\w+\|\d+/)?.[0]??'';
      if(marker&&marker!==lastAuthorityState) {
        process.stdout.write(marker+'\n');
        lastAuthorityState=marker;
      }
      if(/PMLE_HIGH_AWAKE_AUTHORITY_READY\|ACTIVE\|READY\|\d+/.test(marker)) {
        authorityReady=marker;
        break;
      }
      await host.waitForTimeout(500);
    }
    assert.match(authorityReady,
      /PMLE_HIGH_AWAKE_AUTHORITY_READY\|ACTIVE\|READY\|\d+/,
      'high-awake diagnostic authority did not become ready');
  } else {
    await Promise.all([host,guest].map(page=>page.locator('[data-game][data-active]')
      .waitFor({state:'visible',timeout:startupTimeoutMs})));
  }
  if(cadenceObservation) {
    let cadence=null;
    const observationDeadline=Date.now()+10*60*1000;
    while(Date.now()<observationDeadline) {
      const output=dbSql(
        `select 'PMLE_CADENCE_OBSERVATION|'||m.current_tic||'|'||`+
        `nvl(p.tic,0)||'|'||nvl(p.previous_checkpoint_tic,0)||'|'||`+
        `nvl(p.checkpoint_distance,0)||'|'||nvl(p.awake_monsters,0)||'|'||`+
        `nvl(p.checkpoint_decision,'NONE')||'|'||`+
        `nvl((select max(cp.tic) from doom.doom_match_checkpoint cp where `+
        `cp.match_id=m.match_id and cp.generation=m.generation),0)||'|'||`+
        `w.checkpoint_test_hook from doom.doom_match m join `+
        `doom.doom_match_worker_control w on w.match_id=m.match_id `+
        `left join doom.doom_match_checkpoint_probe p on p.match_id=m.match_id `+
        `and p.tic=(select max(q.tic) from doom.doom_match_checkpoint_probe q `+
        `where q.match_id=m.match_id) where m.match_id='${match}';`);
      const row=output.match(
        /PMLE_CADENCE_OBSERVATION\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\w+)\|(\d+)\|(\d+)/);
      if(row&&Number(row[2])>0&&Number(row[7])>=Number(row[2])) {
        cadence={
          frontier:Number(row[1]),probeTic:Number(row[2]),
          previousCheckpoint:Number(row[3]),distance:Number(row[4]),
          awake:Number(row[5]),decision:row[6],
          durableCheckpoint:Number(row[7]),testHook:Number(row[8])
        };
        break;
      }
      await host.waitForTimeout(100);
    }
    assert.ok(cadence,'production checkpoint cadence was not observed');
    assert.equal(cadence.testHook,0,
      'cadence observation accidentally enabled the tic-64 test hook');
    assert.ok(cadence.distance>=128&&cadence.distance<=256,
      'observed checkpoint violated the production cadence bounds');
    assert.equal(cadence.durableCheckpoint,cadence.probeTic,
      'cadence decision did not publish its checkpoint');
    assert.ok(['LOW_AWAKE','FORCED_MAX'].includes(cadence.decision),
      'observed cadence decision was not checkpoint-producing');
    process.stdout.write(`PMLE_CHECKPOINT_CADENCE_OBSERVATION|PASS`+
      `|frontier=${cadence.frontier}|checkpoint_tic=${cadence.probeTic}`+
      `|previous_checkpoint_tic=${cadence.previousCheckpoint}`+
      `|distance=${cadence.distance}|awake=${cadence.awake}`+
      `|decision=${cadence.decision}|checkpoint_test_hook=0\n`);
  } else if(highAwakeRecoveryDiagnostic) {
    // START_READY resets last_seen_at while activating the members. Take
    // browser traffic offline at the authoritative READY boundary, let local
    // in-flight requests settle, then extend the member lease before the
    // worker advances into the hot per-tic lock loop.
    await Promise.all(contexts.map(context=>context.setOffline(true)));
    process.stdout.write('PMLE_HIGH_AWAKE_STAGE|browsers_offline\n');
    await host.waitForTimeout(250);
    const membershipHold=dbSql(
      `update doom.doom_match_member set member_state='ACTIVE',`+
      `disconnected_at=null,leave_tic=null,last_seen_at=`+
      `systimestamp+interval '30' minute where match_id='${match}' `+
      `and member_state in('ACTIVE','DISCONNECTED');\ncommit;\n`+
      `select 'PMLE_HIGH_AWAKE_MEMBERSHIP_HOLD|'||count(*) `+
      `from doom.doom_match_member where match_id='${match}' `+
      `and member_state='ACTIVE' and last_seen_at>systimestamp;`);
    assert.match(membershipHold,/PMLE_HIGH_AWAKE_MEMBERSHIP_HOLD\|2/,
      'high-awake diagnostic did not retain both active members');
    process.stdout.write('PMLE_HIGH_AWAKE_STAGE|membership_held\n');
    assert.ok(highAwakeFeed,'high-awake lobby feed was not prepared');
    const {feedTics,feedBase,feedGeneration,changes}=highAwakeFeed;
    const generationOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_GENERATION_ACTIVE|'||generation from `+
      `doom.doom_match where match_id='${match}';`);
    assert.match(generationOutput,
      new RegExp(`^PMLE_HIGH_AWAKE_GENERATION_ACTIVE\\|${
        feedGeneration}$`,'m'),
      'high-awake match activated a generation other than the preloaded feed');
    const activeFeedOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_FEED_ACTIVE|'||count(*) from `+
      `doom.doom_match_input_event where match_id='${match}' and `+
      `generation=${feedGeneration};`);
    assert.match(activeFeedOutput,
      new RegExp(`^PMLE_HIGH_AWAKE_FEED_ACTIVE\\|${changes.length*2}$`,'m'),
      'high-awake preloaded feed did not survive generation activation');
    process.stdout.write(`PMLE_HIGH_AWAKE_STAGE|feed_active`+
      `|base=${feedBase}|changes=${changes.length}`+
      `|generation=${feedGeneration}\n`);

    let recoveryTarget=null;
    let maxAwakeObserved=0;
    const observationDeadline=Date.now()+20*60*1000;
    while(Date.now()<observationDeadline) {
      const output=dbSql(
        `select 'PMLE_HIGH_AWAKE_WINDOW|'||w.worker_status||'|'||`+
        `replace(nvl(w.last_error,'NONE'),'|','/')||'|'||m.current_tic||'|'||`+
        `w.worker_sid||'|'||w.worker_serial||'|'||nvl(p.tic,0)||'|'||`+
        `nvl(p.previous_checkpoint_tic,0)||'|'||nvl(p.checkpoint_distance,0)||`+
        `'|'||nvl(p.awake_monsters,0)||'|'||nvl(p.checkpoint_decision,'NONE')||`+
        `'|'||(select count(*) from doom.doom_match_checkpoint_probe q `+
        `where q.match_id=m.match_id and q.checkpoint_decision='DEFER_HIGH' `+
        `and q.awake_monsters>16 and q.tic between nvl(p.tic,0)-32 and `+
        `nvl(p.tic,0)) from doom.doom_match m join `+
        `doom.doom_match_worker_control w on w.match_id=m.match_id `+
        `left join doom.doom_match_checkpoint_probe p on p.match_id=m.match_id `+
        `and p.tic=(select max(q.tic) from doom.doom_match_checkpoint_probe q `+
        `where q.match_id=m.match_id) where m.match_id='${match}';`);
      if(!output.includes('PMLE_HIGH_AWAKE_WINDOW|')) {
        throw new Error(
          'high-awake diagnostic match/control row disappeared before recovery target');
      }
      const row=output.match(
        /PMLE_HIGH_AWAKE_WINDOW\|(\w+)\|([^|\r\n]+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\w+)\|(\d+)/);
      if(row) {
        assert.notEqual(row[1],'FAILED',
          `high-awake authority failed before recovery target: ${row[2]}`);
        const frontier=Number(row[3]);
        const previousCheckpoint=Number(row[7]);
        const distance=Number(row[8]);
        const awake=Number(row[9]);
        const decision=row[10];
        const sustainedSamples=Number(row[11]);
        maxAwakeObserved=Math.max(maxAwakeObserved,awake);
        const target=Number(row[6])+16-1;
        const targetDistance=target-previousCheckpoint;
        if(decision==='DEFER_HIGH'&&targetDistance>=240&&awake>16&&
            sustainedSamples>=3&&frontier>=target) {
          recoveryTarget={
            frontier,
            sid:Number(row[4]),
            serial:Number(row[5]),
            probeTic:Number(row[6]),
            previousCheckpoint,
            distance:frontier-previousCheckpoint,
            awake,
            sustainedSamples
          };
          break;
        }
        if(frontier>=feedBase+feedTics) {
          throw new Error(
            `high-awake fixture did not qualify: max_awake=${maxAwakeObserved}`+
            ` threshold=17 through_tic=${frontier}`);
        }
      }
      await host.waitForTimeout(100);
    }
    assert.ok(recoveryTarget,
      'no sustained high-awake maximum-distance recovery window was observed');
    assert.ok(recoveryTarget.distance>=240&&recoveryTarget.distance<=255,
      'authority was not killed at the maximum scheduled pre-checkpoint distance');
    const incarnationOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_KILL_INCARNATION|'||job_name||'|'||`+
      `incarnation_token||'|'||worker_sid||'|'||worker_serial||'|'||`+
      `worker_spid||'|'||worker_job_run from doom.doom_mle_warm_slot `+
      `where assigned_match='${match}' and assigned_role='AUTHORITY' `+
      `and worker_sid=${recoveryTarget.sid} and `+
      `worker_serial=${recoveryTarget.serial};`);
    const incarnation=incarnationOutput.match(
      /^PMLE_HIGH_AWAKE_KILL_INCARNATION\|([A-Z0-9_$#]+)\|([0-9a-f]{32})\|(\d+)\|(\d+)\|(\d+)\|([0-9a-f]{32}:\d+)$/m);
    assert.ok(incarnation,
      'high-awake kill target was not bound to a complete warm-slot incarnation');
    const recoveryStarted=Date.now();
    dbSql(`begin\n`+
      `  execute immediate 'alter system kill session ''${recoveryTarget.sid},`+
      `${recoveryTarget.serial}'' immediate';\n`+
      `exception when others then\n`+
      `  if sqlcode<>-31 then raise;end if;\n`+
      `end;\n/`);
    const killedOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_KILLED|'||m.current_tic||'|'||`+
      `nvl((select max(cp.tic) from doom.doom_match_checkpoint cp where `+
      `cp.match_id=m.match_id and cp.generation=m.generation),0) `+
      `from doom.doom_match m where m.match_id='${match}';`);
    const killed=killedOutput.match(/PMLE_HIGH_AWAKE_KILLED\|(\d+)\|(\d+)/);
    assert.ok(killed,'maximum-distance durable killed frontier missing');
    const killedFrontier=Number(killed[1]);
    const killedCheckpoint=Number(killed[2]);
    const killedDistance=killedFrontier-killedCheckpoint;
    assert.ok(killedDistance>=240&&killedDistance<=255,
      'durable kill did not occur at maximum pre-checkpoint distance');
    const recoveryOutput=await dbSqlAsync(`
declare
  l_state varchar2(16);
begin
  doom.doom_match_worker.recover_match('${match}',180000,l_state);
  dbms_output.put_line('PMLE_HIGH_AWAKE_RECOVERY_RESULT|'||l_state);
end;
/`);
    assert.match(recoveryOutput,/PMLE_HIGH_AWAKE_RECOVERY_RESULT\|ACTIVE/,
      'maximum-distance high-awake recovery did not publish');
    const recoveryElapsedMs=Date.now()-recoveryStarted;
    // The killed retained session cannot honor its own stop intent. Reset its
    // exact dead incarnation after recovery so diagnostic cleanup cannot
    // strand a RUNNING slot or consume future match capacity.
    dbSql(`begin doom.doom_worker_lifecycle.stop_job(`+
      `'${incarnation[1]}',true,'high-awake killed authority cleanup',`+
      `'${incarnation[2]}',${incarnation[3]},${incarnation[4]},`+
      `'${incarnation[5]}','${incarnation[6]}');end;\n/`);
    const recoveredOutput=dbSql(
      `select 'PMLE_HIGH_AWAKE_RECOVERED|'||generation||'|'||current_tic `+
      `from doom.doom_match where match_id='${match}';`);
    const recovered=recoveredOutput.match(
      /PMLE_HIGH_AWAKE_RECOVERED\|(\d+)\|(\d+)/);
    assert.ok(recovered,'maximum-distance recovered frontier missing');
    assert.equal(Number(recovered[2]),killedFrontier,
      'maximum-distance recovery changed the confirmed frontier');
    // This timer starts at the kill and covers restore, replay, and publish.
    // Production detection consumes up to the 15-second backstop separately,
    // leaving approximately 45 seconds of the end-to-end 60-second SLA.
    const recoveryPhaseVerdict=recoveryElapsedMs<=45000?'PASS':'FAIL';
    const estimatedTotalMs=recoveryElapsedMs+15000;
    const recoveryVerdict=estimatedTotalMs<=60000?'PASS':'FAIL';
    process.stdout.write(`PMLE_HIGH_AWAKE_RECOVERY|${
      highAwakeRecoveryGate?recoveryVerdict:'DIAGNOSTIC_NOT_GATE'}`+
      `|probe_tic=${recoveryTarget.probeTic}`+
      `|checkpoint_tic=${killedCheckpoint}`+
      `|frontier=${killedFrontier}`+
      `|distance=${killedDistance}`+
      `|awake=${recoveryTarget.awake}`+
      `|sustained_samples=${recoveryTarget.sustainedSamples}`+
      `|elapsed_ms=${recoveryElapsedMs}`+
      `|detection_budget_ms=15000`+
      `|estimated_total_ms=${estimatedTotalMs}`+
      `|phase_budget_45s=${recoveryPhaseVerdict}`+
      `|sla_60s=${recoveryVerdict}\n`);
    if(highAwakeRecoveryGate) {
      assert.equal(recoveryPhaseVerdict,'PASS',
        'maximum-distance restore/replay/publish exceeded its 45-second phase budget');
    }
  } else if(doubleRecoveryDiagnostic) {
    // Stop client traffic first. A public poll is itself a recovery trigger,
    // so leaving the browser online would contaminate the intended two-caller
    // race with a third participant.
    await Promise.all(contexts.map(context=>context.setOffline(true)));
    const initialOutput=dbSql(
      `select 'PMLE_RECOVERY_RACE_INITIAL|'||m.generation||'|'||`+
      `w.worker_sid||'|'||w.worker_serial||'|'||`+
      `nvl((select max(assignment_id) from `+
      `doom.doom_mle_warm_assignment),0) from doom.doom_match m join `+
      `doom.doom_match_worker_control w on w.match_id=m.match_id `+
      `where m.match_id='${match}';`);
    const initial=initialOutput.match(
      /PMLE_RECOVERY_RACE_INITIAL\|(\d+)\|(\d+)\|(\d+)\|(\d+)/);
    assert.ok(initial,'double-recovery initial incarnation evidence missing');
    const initialGeneration=Number(initial[1]);
    const authoritySid=Number(initial[2]);
    const authoritySerial=Number(initial[3]);
    const baselineAssignment=Number(initial[4]);

    // Deliberately vacate the match-bound tier-1 standby. Its retained worker
    // returns to READY/unbound, which makes tier 2 the highest available rung.
    dbSql(`update doom.doom_match_standby_control set stop_requested=1 `+
      `where match_id='${match}' and standby_status='READY';\ncommit;`);
    let tier2Ready=false;
    for(let attempt=0;attempt<120;attempt++) {
      const output=dbSql(
        `select 'PMLE_RECOVERY_RACE_TIER2|'||`+
        `(select count(*) from doom.doom_mle_warm_slot where `+
        `slot_status='READY' and assigned_match is null and `+
        `assigned_role is null)||'|'||nvl((select standby_status from `+
        `doom.doom_match_standby_control where match_id='${match}'),'NONE') `+
        `from dual;`);
      const row=output.match(/PMLE_RECOVERY_RACE_TIER2\|(\d+)\|(\w+)/);
      if(row&&Number(row[1])===1&&row[2]==='STOPPED') {
        tier2Ready=true;
        break;
      }
      await host.waitForTimeout(250);
    }
    assert.ok(tier2Ready,'tier-2 unbound warm slot did not become ready');
    dbSql(`alter system kill session '${authoritySid},${authoritySerial}' immediate;`);

    const callerSql=caller=>`
declare
  l_state varchar2(16);
begin
  dbms_session.sleep(2);
  doom.doom_match_worker.recover_match('${match}',180000,l_state);
  dbms_output.put_line('PMLE_RECOVERY_RACE_CALL|caller=${caller}|result='||
    l_state);
exception when others then
  dbms_output.put_line('PMLE_RECOVERY_RACE_CALL|caller=${caller}|result=ERROR'||
    '|sqlcode='||sqlcode||'|message='||replace(substr(sqlerrm,1,300),'|','/'));
end;
/`;
    const raceOutputs=await Promise.all([
      dbSqlAsync(callerSql(1)),
      dbSqlAsync(callerSql(2))
    ]);
    process.stdout.write(raceOutputs.join(''));

    const finalOutput=dbSql(
      `select 'PMLE_RECOVERY_RACE_FINAL|'||m.generation||'|'||`+
      `w.generation||'|'||w.worker_status||'|'||`+
      `(select count(*) from doom.doom_mle_warm_assignment a where `+
      `a.assignment_id>${baselineAssignment} and a.match_id=m.match_id `+
      `and a.assigned_role='AUTHORITY') from doom.doom_match m join `+
      `doom.doom_match_worker_control w on w.match_id=m.match_id `+
      `where m.match_id='${match}';`);
    const final=finalOutput.match(
      /PMLE_RECOVERY_RACE_FINAL\|(\d+)\|(\d+)\|(\w+)\|(\d+)/);
    assert.ok(final,'double-recovery final fence evidence missing');
    assert.equal(Number(final[1]),initialGeneration+1,
      'double recovery advanced the match generation more than once');
    assert.equal(Number(final[2]),initialGeneration+1,
      'double recovery published more than one control generation');
    assert.equal(final[3],'READY','winning tier-2 authority is not ready');
    assert.equal(Number(final[4]),1,
      'double recovery produced other than one tier-2 assignment');
    const activeCalls=raceOutputs.filter(output=>
      /PMLE_RECOVERY_RACE_CALL\|caller=\d+\|result=ACTIVE/.test(output)).length;
    const rejectedCalls=raceOutputs.filter(output=>
      /PMLE_RECOVERY_RACE_CALL\|caller=\d+\|result=ERROR/.test(output)).length;
    assert.equal(activeCalls,1,'exactly one recovery caller must publish');
    assert.equal(rejectedCalls,1,'losing recovery caller was not fenced');
    process.stdout.write(`PMLE_DOUBLE_RECOVERY|PASS|match=${match}`+
      `|generation=${initialGeneration}->${Number(final[1])}`+
      `|tier2_assignments=1|winner=1|loser_fenced=1\n`);
  } else if(checkpointLivenessDiagnostic) {
    let frontier=0;let generation=0;let workerStatus='';let checkpointTic=0;
    let checkpointAttemptTic=0;
    const deadline=Date.now()+600000;
    let killStarted=0;let killed=false;
    while(Date.now()<deadline) {
      const output=dbSql(
        `select 'PMLE_CHECKPOINT_FRONTIER|'||m.current_tic||'|'||`+
        `m.generation||'|'||w.worker_status||'|'||w.worker_sid||'|'||`+
        `w.worker_serial||'|'||nvl((select action from v$session s where `+
        `s.sid=w.worker_sid and s.serial#=w.worker_serial),'NO_SESSION') `+
        `||'|'||nvl((select standby_status from `+
        `doom.doom_match_standby_control sc where sc.match_id=m.match_id),`+
        `'NONE')||'|'||nvl((select max(cp.tic) from `+
        `doom.doom_match_checkpoint cp where cp.match_id=m.match_id),0) `+
        `from doom.doom_match m join `+
        `doom.doom_match_worker_control w on w.match_id=m.match_id `+
        `where m.match_id='${match}';`);
      const row=output.match(
        /PMLE_CHECKPOINT_FRONTIER\|(\d+)\|(\d+)\|(\w+)\|(\d+)\|(\d+)\|(\w+)\|(\w+)\|(\d+)/);
      if(row) {
        frontier=Number(row[1]);generation=Number(row[2]);workerStatus=row[3];
        checkpointTic=Number(row[8]);
        if(killCheckpointDiagnostic&&!killed&&row[6]==='MLE_CHECKPOINT'&&
            row[7]==='READY') {
          checkpointAttemptTic=frontier+1;
          killStarted=Date.now();
          dbSql(`alter system kill session '${row[4]},${row[5]}' immediate;`);
          killed=true;
          process.stdout.write(`PMLE_CHECKPOINT_KILL|sid=${row[4]}`+
            `|serial=${row[5]}\n`);
        }
        if(killCheckpointDiagnostic) {
          if(killed&&generation>1&&frontier>=checkpointAttemptTic) break;
        } else if((checkpointTic>0&&frontier>=checkpointTic+8)||
            generation!==1) break;
      }
      await host.waitForTimeout(250);
    }
    const slowOutput=dbSql(
      `select 'PMLE_CHECKPOINT_SLOW|'||tic||'|'||round(elapsed_ms,3)||'|'||`+
      `nvl(round(pre_mle_ms,3),-1)||'|'||nvl(round(mle_ms,3),-1)||'|'||`+
      `nvl(round(post_mle_ms,3),-1)||'|'||nvl(round(commit_ms,3),-1) `+
      `||'|'||nvl(round(checkpoint_save_ms,3),-1)||'|'||`+
      `nvl(round(checkpoint_publish_ms,3),-1) `+
      `from doom.doom_match_slow_call where match_id='${match}' `+
      `and checkpoint_save_ms is not null `+
      `order by tic desc,generation desc fetch first 1 row only;`);
    process.stdout.write(`PMLE_CHECKPOINT_LIVENESS|match=${match}|tic=${frontier}`+
      `|checkpoint_tic=${checkpointTic}|checkpoint_attempt_tic=`+
      `${checkpointAttemptTic}|generation=${generation}`+
      `|worker=${workerStatus}\n${slowOutput}`);
    const exercisedCheckpoint=killCheckpointDiagnostic?
      checkpointAttemptTic:checkpointTic;
    const minimumExpectedCheckpoint=routeDiagnostics?64:128;
    assert.ok(exercisedCheckpoint>=minimumExpectedCheckpoint&&
      exercisedCheckpoint<=256,
      'authority did not exercise a checkpoint inside the cadence bound');
    assert.ok(frontier>=exercisedCheckpoint,
      'authority did not cross the discovered checkpoint');
    if(killCheckpointDiagnostic) {
      assert.ok(killed,'authority never exposed the checkpoint action');
      assert.ok(generation>1,'killed checkpoint session did not recover');
      const recoveryMs=Date.now()-killStarted;
      process.stdout.write(`PMLE_CHECKPOINT_RECOVERY|elapsed_ms=${recoveryMs}\n`);
      assert.ok(recoveryMs<=60000,
        'killed checkpoint session exceeded the 60 s recovery bound');
    } else {
      assert.equal(generation,1,'REST recovered during a legitimate checkpoint');
      const probeOutput=dbSql(
        `select 'PMLE_LIVENESS_DECISION|'||decision from `+
        `doom.doom_match_liveness_probe where match_id='${match}' `+
        `order by probe_id;`);
      process.stdout.write(probeOutput);
      assert.match(probeOutput,/PMLE_LIVENESS_DECISION\|SUPPRESS_BUSY/,
        'slow checkpoint did not exercise the primary busy lease');
    }
    assert.equal(workerStatus,'READY');
  } else {
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>
    /TIC [1-9][0-9]*/.test(document.querySelector('[data-hud]')?.textContent??''),
    null,{timeout:30000})));
  await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
    const text=document.querySelector('[data-hud]')?.textContent??'';
    const tic=Number(text.match(/TIC (\d+)/)?.[1]??0);
    const server=Number(text.match(/SERVER (\d+)/)?.[1]??999);
    return text.includes('confirmed-only')&&window.__doomSoakTics.length>=40&&
      server-tic<=8;
  },null,{timeout:progressTimeoutMs})));
  let backgroundSummary='';
  const warmupStarted=Date.now();
  if(wanBackgroundScenario) {
    const presentationBefore=await guest.evaluate(()=>window.__doomSoakTics.length);
    // Headless Chromium deliberately keeps every page "visible". Shadow the
    // standard readonly Document property on this test page, then dispatch the
    // real lifecycle event; production code has no test-only control surface.
    await guest.evaluate(()=>{
      Object.defineProperty(document,'hidden',{configurable:true,get:()=>true});
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await guest.waitForFunction(()=>document.hidden&&
      window.__doomWanVisibility.some(value=>
        value.state==='hidden'&&value.strategy==='suspend'));
    await host.waitForTimeout(2000);
    assert.equal(heldPollLeases(match,1),0,
      'hidden guest retained a DMB1 poll lease');
    await guest.waitForFunction(()=>window.__doomWanVisibility.some(value=>
      value.state==='hidden'&&value.strategy==='poll-lease-released'));
    await host.waitForTimeout(10000);
    await guest.evaluate(()=>{
      Object.defineProperty(document,'hidden',{configurable:true,get:()=>false});
      document.dispatchEvent(new Event('visibilitychange'));
    });
    try {
      await guest.waitForFunction(()=>!document.hidden&&
        window.__doomWanVisibility.some(value=>
          value.state==='visible'&&value.strategy==='checkpoint-resync'),
        null,{timeout:60000});
    } catch (cause) {
      const diagnostic=await guest.evaluate(()=>({
        hidden:document.hidden,
        hud:document.querySelector('[data-hud]')?.textContent??'',
        hudError:document.querySelector('[data-hud]')?.classList.contains('error'),
        visibility:window.__doomWanVisibility,
        resyncs:window.__doomSoakResyncs
      }));
      process.stdout.write(`PMLE_WAN_BACKGROUND|FAIL|diagnostic=${
        JSON.stringify(diagnostic)}\n`);
      throw cause;
    }
    await guest.waitForFunction(before=>window.__doomSoakTics.length>=before+40,
      presentationBefore,{timeout:60000});
    const visibility=await guest.evaluate(()=>window.__doomWanVisibility);
    const checkpoint=visibility.findLast(value=>
      value.state==='visible'&&value.strategy==='checkpoint-resync');
    assert.ok(checkpoint?.hiddenMs>=5000,
      'background checkpoint staleness threshold was not exercised');
    backgroundSummary=` hiddenMs=${checkpoint.hiddenMs.toFixed(1)}`+
      ` checkpointTic=${checkpoint.frontierTic} leasesAfter2s=0 resumed=1`;
    process.stdout.write(`PMLE_WAN_BACKGROUND|PASS|profile_rtt_ms=${wanRttMs}|`+
      `hidden_ms=${checkpoint.hiddenMs.toFixed(1)}|checkpoint_tic=`+
      `${checkpoint.frontierTic}|leases_after_2s=0|presentations_after_focus=40\n`);
  }
  if (warmupSeconds>0) {
    const remaining=warmupSeconds*1000-(Date.now()-warmupStarted);
    if(remaining>0) await host.waitForTimeout(remaining);
  }
  const measurementStarts=await Promise.all([host,guest].map(page=>
    page.evaluate(()=>performance.now())));
  const ticOf=async page=>Number((await page.locator('[data-hud]').textContent()??'')
    .match(/TIC (\d+)/)?.[1]??0);
  const starts=await Promise.all([host,guest].map(ticOf));
  const startCounts=await Promise.all([host,guest].map(page=>page.evaluate(()=>
    window.__doomSoakTics.length)));
  let pressed=false;let samples=0;let maxLag=0;let memoryBaseline=null;
  const reconnectSamples=[0,0];let maxReconnectSamples=0;
  const startedAt=Date.now();
  const deadline=Date.now()+seconds*1000;
  while (Date.now()<deadline) {
    pressed=!pressed;
    await Promise.all([host,guest].map(page=>pressed?page.keyboard.down('w'):page.keyboard.up('w')));
    await host.waitForTimeout(500);
    if (samples%10===0) {
      const hudRows=await Promise.all([host,guest].map(page=>page.locator('[data-hud]')
        .evaluate(element=>({text:element.textContent??'',error:element.classList.contains('error')}))));
      for (const [slot,row] of hudRows.entries()) {
        assert.equal(row.error,false,row.text);
        if (row.text.includes('Reconnecting to Oracle')) {
          reconnectSamples[slot]+=1;maxReconnectSamples=Math.max(maxReconnectSamples,
            reconnectSamples[slot]);
          assert.ok(reconnectSamples[slot]<=6,
            `soak player ${slot} reconnect exceeded 30 seconds`);
          continue;
        }
        reconnectSamples[slot]=0;
        const tic=Number(row.text.match(/TIC (\d+)/)?.[1]??0);
        const server=Number(row.text.match(/SERVER (\d+)/)?.[1]??999);
        const lag=server-tic;
        assert.ok(lag<128,`soak presentation lag exceeded retention ring: ${row.text}`);
        maxLag=Math.max(maxLag,lag);
      }
    }
    if (seconds>=120&&memoryBaseline===null&&Date.now()-startedAt>=60000)
      memoryBaseline=workerMemory(match);
    samples+=1;
  }
  await Promise.all([host,guest].map(page=>page.keyboard.up('w')));
  if(wanGate) {
    // A recovery in the final instant of the scored window must still prove
    // a continuous confirmed tail. Extend observation, never shorten or
    // discard the completed scoring interval.
    await Promise.all([host,guest].map(page=>page.waitForFunction(()=>{
      const last=window.__doomSoakResyncs.at(-1)?.atCount??0;
      return window.__doomSoakTics.length-last>=40;
    },null,{timeout:60000})));
  }
  const ends=await Promise.all([host,guest].map(ticOf));
  const evidence=await Promise.all([host,guest].map((page,slot)=>page.evaluate(
    ({start,measurementStart})=>({
      presented:window.__doomSoakTics.slice(start),
      paintAt:window.__doomSoakPaintAt.slice(start),
      resyncs:window.__doomSoakResyncs.filter(value=>value.atCount>=start)
        .map(value=>({...value,atCount:value.atCount-start})),
      inputs:window.__doomWanInputs.filter(value=>value.at>=measurementStart),
      effective:window.__doomWanEffective.filter(value=>value.at>=measurementStart),
      lead:window.__doomWanLead.filter(value=>value.at>=measurementStart),
      confirmed:window.__doomWanConfirmed.filter(value=>value.at>=measurementStart),
      batches:window.__doomWanBatches.filter(value=>value.at>=measurementStart),
      presentedDetails:window.__doomWanPresented.filter(value=>
        value.at>=measurementStart)
    }),{start:startCounts[slot],measurementStart:measurementStarts[slot]})));
  const presented=evidence.map(value=>value.presented);
  const paintTails=[];
  const wanMetrics=[];
  const percentile=(values,fraction)=>{
    assert.ok(values.length>0,'WAN percentile requires samples');
    const ordered=[...values].sort((a,b)=>a-b);
    return ordered[Math.max(0,Math.ceil(ordered.length*fraction)-1)];
  };
  for (let slot=0;slot<2;slot++) {
    process.stdout.write(`PMLE_SOAK_BROWSER_DIAG|slot=${slot}`+
      `|presented=${presented[slot].length}`+
      `|advanced=${ends[slot]-starts[slot]}`+
      `|resyncs=${evidence[slot].resyncs.length}`+
      `|last_resync_at=${evidence[slot].resyncs.at(-1)?.atCount??0}\n`);
    assert.ok(presented[slot].length>=seconds*25,
      `soak player ${slot} presented ${presented[slot].length} frames`);
    assert.equal(evidence[slot].paintAt.length,presented[slot].length,
      `soak player ${slot} paint/tic trace mismatch`);
    const gaps=[];
    for (let index=1;index<presented[slot].length;index+=1) {
      assert.ok(presented[slot][index]>presented[slot][index-1],
        `soak player ${slot} repeated or reversed tic ${presented[slot][index-1]}`);
      if (presented[slot][index]!==presented[slot][index-1]+1) gaps.push(index);
    }
    const timed=evidence[slot].paintAt;
    const intervals=timed.slice(1).map((at,index)=>at-timed[index]);
    assert.ok(intervals.length>0,`soak player ${slot} has no paint intervals`);
    const ordered=[...intervals].sort((a,b)=>a-b);
    paintTails.push({p999:ordered[Math.ceil(ordered.length*.999)-1],
      max:ordered.at(-1)});
    assert.ok(gaps.length<=evidence[slot].resyncs.length,
      `soak player ${slot} skipped without a recorded authoritative resync`);
    const finalStart=evidence[slot].resyncs.at(-1)?.atCount??0;
    assert.ok(presented[slot].length-finalStart>=40,
      `soak player ${slot} final post-resync run is too short`);
    for (let index=Math.max(1,finalStart+1);index<presented[slot].length;index+=1)
      assert.equal(presented[slot][index],presented[slot][index-1]+1,
        `soak player ${slot} final run skipped tic ${presented[slot][index-1]}`);
    assert.ok(ends[slot]-starts[slot]>=seconds*25,
      `soak player ${slot} advanced ${ends[slot]-starts[slot]} tics`);
    if(wanGate) {
      const inputBySequence=new Map(evidence[slot].inputs.map(value=>
        [value.inputSequence,value]));
      const effectLatencies=[];const roundTrips=[];const latencyParts=[];
      let priorLead=null;
      for(const effective of evidence[slot].effective) {
        roundTrips.push(effective.roundTripMs);
        if(priorLead===null) {
          priorLead=effective.leadTics;
        } else if(effective.leadTics!==priorLead) {
          assert.equal(Math.abs(effective.leadTics-priorLead),1,
            `WAN player ${slot} lead jumped`);
          priorLead=effective.leadTics;
        }
        const input=inputBySequence.get(effective.inputSequence);
        if(input===undefined) continue;
        const confirmed=evidence[slot].confirmed.find(value=>
          value.tic>=effective.effectiveTic&&value.at>=effective.at);
        const presentedIndex=evidence[slot].presented.findIndex((tic,index)=>
          tic>=effective.effectiveTic&&evidence[slot].paintAt[index]>=input.at);
        if(presentedIndex>=0) {
          const presentedAt=evidence[slot].paintAt[presentedIndex];
          effectLatencies.push(presentedAt-input.at);
          latencyParts.push({
            queueAndPostMs:effective.at-input.at,
            roundTripMs:effective.roundTripMs,
            acceptedToConfirmedMs:confirmed===undefined ? null :
              confirmed.at-effective.at,
            confirmedToPresentedMs:confirmed===undefined ? null :
              presentedAt-confirmed.at,
            totalMs:presentedAt-input.at,
            inputSequence:effective.inputSequence,
            effectiveTic:effective.effectiveTic
          });
        }
      }
      assert.ok(effectLatencies.length>=Math.max(20,seconds),
        `WAN player ${slot} has too few input/presentation pairs`);
      assert.ok(roundTrips.length>=Math.max(20,seconds),
        `WAN player ${slot} has too few RTT samples`);
      for(let index=0;index<evidence[slot].lead.length;index+=1) {
        const current=evidence[slot].lead[index];
        assert.equal(Math.abs(current.to-current.from),1,
          `WAN player ${slot} lead adjustment jumped`);
        if(index>0) {
          const prior=evidence[slot].lead[index-1];
          assert.equal(current.from,prior.to,
            `WAN player ${slot} lead adjustment chain broke`);
          assert.ok(current.at-prior.at>=9990,
            `WAN player ${slot} lead oscillated inside ten seconds`);
        }
      }
      for(let index=1;index<evidence[slot].confirmed.length;index+=1) {
        assert.ok(evidence[slot].confirmed[index].tic>
          evidence[slot].confirmed[index-1].tic,
        `WAN player ${slot} confirmed tic regressed`);
        assert.ok(evidence[slot].confirmed[index].generation>=
          evidence[slot].confirmed[index-1].generation,
        `WAN player ${slot} generation regressed`);
      }
      const p95=percentile(effectLatencies,.95);
      const rttP90=percentile(roundTrips,.90);
      const maxLead=Math.max(...evidence[slot].effective.map(value=>value.leadTics));
      const maxPlayout=Math.max(1,...evidence[slot].presentedDetails.map(value=>
        value.playoutTics));
      // A configured long-poll hold is an idle timeout, never acceptable
      // post-commit delivery delay. End-to-presentation permits the injected
      // RTT/jitter, the selected input lead and confirmed playout offset, plus
      // one authoritative processing tic.
      const limit=wanRttMs+wanJitterMs+(maxLead+maxPlayout+1)*(1000/35);
      const numericPart=(name)=>latencyParts.map(value=>value[name])
        .filter(value=>typeof value==='number'&&Number.isFinite(value));
      const componentSummary={
        samples:latencyParts.length,
        totalP50Ms:percentile(effectLatencies,.50),
        totalP90Ms:percentile(effectLatencies,.90),
        totalP95Ms:p95,
        totalMaxMs:Math.max(...effectLatencies),
        queueAndPostP95Ms:percentile(numericPart('queueAndPostMs'),.95),
        postRoundTripP95Ms:percentile(numericPart('roundTripMs'),.95),
        acceptedToConfirmedP95Ms:
          percentile(numericPart('acceptedToConfirmedMs'),.95),
        confirmedToPresentedP95Ms:
          percentile(numericPart('confirmedToPresentedMs'),.95),
        batchWallP95Ms:percentile(evidence[slot].batches.map(value=>value.wallMs),.95),
        batchHoldP95Ms:
          percentile(evidence[slot].batches.map(value=>value.holdElapsedMs),.95),
        batchCountP95:percentile(evidence[slot].batches.map(value=>value.count),.95),
        presentationLagP50Tics:percentile(evidence[slot].presentedDetails.map(
          value=>value.presentationLagTics),.50),
        presentationLagP95Tics:percentile(evidence[slot].presentedDetails.map(
          value=>value.presentationLagTics),.95),
        presentationLagMaxTics:Math.max(...evidence[slot].presentedDetails.map(
          value=>value.presentationLagTics)),
        worst:latencyParts.toSorted((left,right)=>right.totalMs-left.totalMs).slice(0,5)
      };
      process.stdout.write(`PMLE_WAN_LATENCY_DIAG|slot=${slot}|`+
        `${JSON.stringify(componentSummary)}\n`);
      assert.ok(p95<=limit,
        `WAN player ${slot} input/presentation p95 `+
        `${p95.toFixed(1)} > ${limit.toFixed(1)}`);
      const p99Interval=percentile(intervals,.99);
      assert.ok(p99Interval<=2*(1000/35),
        `WAN player ${slot} presentation p99 ${p99Interval.toFixed(1)} ms`);
      wanMetrics.push({inputPresentationP95Ms:p95,rttP90Ms:rttP90,maxLead,
        maxPlayout,
        leadChanges:evidence[slot].lead.length,presentationP99Ms:p99Interval});
    }
  }

  const sql=`set serveroutput on size unlimited feedback off heading off linesize 32767\n`+
    `declare t number;f number;c number;cmd number;b number;w varchar2(16);`+
    `disconnected number;deadline number;left_ number;initials number;`+
    `sampled number;neutral number;begin\n`+
    `select m.current_tic,`+
    `(select count(*) from doom_match_frame f where f.match_id=m.match_id),`+
    `(select count(*) from doom_match_checkpoint c where c.match_id=m.match_id),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id),`+
    `(select coalesce(sum(f.response_bytes),0) from doom_match_frame f where f.match_id=m.match_id),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_DISCONNECTED' and d.tic>=${Math.min(...starts)}),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_DEADLINE'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_LEFT'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='NEUTRAL_INITIAL'),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source='SAMPLED_INPUT' and d.tic>=${Math.min(...starts)}),`+
    `(select count(*) from doom_match_command d where d.match_id=m.match_id and `+
    `d.command_source like 'NEUTRAL_%' and d.tic>=${Math.min(...starts)}),`+
    `(select worker_status from doom_match_worker_control w where w.match_id=m.match_id) `+
    `into t,f,c,cmd,b,disconnected,deadline,left_,initials,sampled,neutral,w `+
    `from doom_match m where m.match_id='${match}';\n`+
    `dbms_output.put_line('SOAK_DB|tic='||t||'|frames='||f||'|checkpoints='||c||`+
    `'|commands='||cmd||'|bytes='||b||'|disconnectedNeutral='||disconnected||`+
    `'|deadlineNeutral='||deadline||'|leftNeutral='||left_||`+
    `'|initialNeutral='||initials||'|sampled='||sampled||`+
    `'|neutral='||neutral||'|worker='||w);end;\n/\n`;
  const output=execFileSync('scripts/db_sql.sh',['-'],{input:sql,encoding:'utf8'});
  const row=output.match(/SOAK_DB\|tic=(\d+)\|frames=(\d+)\|checkpoints=(\d+)\|commands=(\d+)\|bytes=(\d+)\|disconnectedNeutral=(\d+)\|deadlineNeutral=(\d+)\|leftNeutral=(\d+)\|initialNeutral=(\d+)\|sampled=(\d+)\|neutral=(\d+)\|worker=(\w+)/);
  assert.ok(row,'soak database evidence missing');
  const [,tic,frames,checkpoints,commands,bytes,disconnectedNeutral,
    deadlineNeutral,leftNeutral,initialNeutral,sampled,neutral,worker]=row;
  assert.equal(worker,'READY');assert.ok(Number(frames)<=258);
  assert.ok(Number(checkpoints)<=2);
  assert.equal(Number(deadlineNeutral),0);assert.equal(Number(leftNeutral),0);
  const totalResyncs=evidence.reduce((sum,value)=>sum+value.resyncs.length,0);
  assert.ok(Number(disconnectedNeutral)===0||totalResyncs>0||maxReconnectSamples>0,
    'disconnect neutralization lacked a recorded client recovery');
  assert.ok(Number(disconnectedNeutral)<=Math.max(1,totalResyncs)*35*30,
    `disconnect neutralization exceeded recovery bound: ${disconnectedNeutral}`);
  assert.ok(Number(commands)>=Number(tic)*2&&Number(commands)<=(Number(tic)+2)*2,
    `command frontier commands=${commands} tic=${tic}`);
  assert.ok(Number(bytes)<=258*65536);
  if(wanGate) {
    const substitutionRate=Number(neutral)/
      Math.max(1,Number(sampled)+Number(neutral));
    assert.ok(substitutionRate<.005,
      `WAN neutral substitution rate ${substitutionRate}`);
    process.stdout.write(`PMLE_WAN_GATE|PASS|rtt_ms=${wanRttMs}`+
      `|jitter_ms=${wanJitterMs}|seconds=${seconds}`+
      `|neutral_rate=${substitutionRate.toFixed(6)}|players=`+
      `${wanMetrics.map(value=>[
        value.inputPresentationP95Ms.toFixed(1),value.rttP90Ms.toFixed(1),
        value.maxLead,value.maxPlayout,value.leadChanges,
        value.presentationP99Ms.toFixed(1)
      ].join('/')).join(',')}${backgroundSummary}\n`);
  }
  let memorySummary='';
  if (memoryBaseline!==null) {
    const memoryFinal=workerMemory(match);const allowance=64*1024*1024;
    assert.equal(memoryBaseline.sessions,1);assert.equal(memoryFinal.sessions,1);
    assert.ok(memoryFinal.doomSessions<=memoryBaseline.doomSessions+1,
      `DOOM sessions grew baseline=${memoryBaseline.doomSessions} final=${memoryFinal.doomSessions}`);
    assert.ok(memoryFinal.pga<=memoryBaseline.pga+allowance,
      `worker PGA grew baseline=${memoryBaseline.pga} final=${memoryFinal.pga}`);
    assert.ok(memoryFinal.uga<=memoryBaseline.uga+allowance,
      `worker UGA grew baseline=${memoryBaseline.uga} final=${memoryFinal.uga}`);
    assert.ok(memoryFinal.javaSession<=memoryBaseline.javaSession+allowance,
      `worker Java session heap grew baseline=${memoryBaseline.javaSession} final=${memoryFinal.javaSession}`);
    memorySummary=` memory=${memoryBaseline.pga}/${memoryFinal.pga}`+
      ` java=${memoryBaseline.javaSession}/${memoryFinal.javaSession}`+
      ` gc=${memoryBaseline.gc}/${memoryFinal.gc}`;
  }
  process.stdout.write(`PASS P13.5-MULTIPLAYER-SOAK seconds=${seconds} `+
    `warmupSeconds=${warmupSeconds} `+
    `tics=${starts.join('/')}-${ends.join('/')} maxLag=${maxLag} `+
    `maxReconnectSeconds=${maxReconnectSamples*5} `+
    `resyncs=${evidence.map(value=>value.resyncs.length).join('/')} `+
    `frames=${frames} checkpoints=${checkpoints} bytes=${bytes} `+
    `disconnectedNeutral=${disconnectedNeutral} initialNeutral=${initialNeutral} `+
    `paint999Max=${paintTails.map(value=>`${value.p999.toFixed(1)}/${value.max.toFixed(1)}`).join(',')}${memorySummary}\n`);
  }
} finally {
  await browser.close();
}
