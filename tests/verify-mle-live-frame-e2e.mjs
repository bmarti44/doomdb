#!/usr/bin/env node
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';

const root = new URL(process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/');
const timeoutMs = Number(process.env.DOOMDB_LIVE_FRAME_TIMEOUT_MS ?? 120_000);
const batchSoakPolls = Number(
  process.env.DOOMDB_LIVE_FRAME_BATCH_SOAK_POLLS ?? 0);
const ringWrapMode = process.env.DOOMDB_LIVE_FRAME_RING_WRAP ?? 'NO';
const recoveryMode = process.env.DOOMDB_LIVE_FRAME_RECOVERY ?? 'NO';
const captureDir = process.env.DOOMDB_LIVE_FRAME_CAPTURE_DIR;
const expectedSlot = process.env.DOOMDB_LIVE_FRAME_EXPECTED_SLOT === undefined
  ? undefined : Number(process.env.DOOMDB_LIVE_FRAME_EXPECTED_SLOT);
assert.ok(Number.isInteger(timeoutMs) && timeoutMs >= 10_000);
assert.ok(Number.isInteger(batchSoakPolls) &&
  batchSoakPolls >= 0 && batchSoakPolls <= 1_000);
assert.ok(['NO','YES'].includes(ringWrapMode));
assert.ok(['NO','YES'].includes(recoveryMode));
assert.ok(expectedSlot === undefined
  || Number.isInteger(expectedSlot) && expectedSlot >= 1 && expectedSlot <= 2);

const dbSqlPath=process.env.DOOMDB_DB_SQL_CLIENT ??
  fileURLToPath(new URL('../scripts/db_sql.sh',import.meta.url));
const repository=fileURLToPath(new URL('../',import.meta.url));
function dbSql(sql) {
  return new Promise((resolve,reject)=>{
    const child=spawn(dbSqlPath,['-'],{stdio:['pipe','pipe','pipe']});
    let stdout='',stderr='';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data',chunk=>{stdout+=chunk;});
    child.stderr.on('data',chunk=>{stderr+=chunk;});
    child.on('error',reject);
    child.on('close',status=>{
      if(status===0)resolve(stdout);
      else reject(new Error(
        `database diagnostic failed (${status}): ${stdout}${stderr}`));
    });
    child.stdin.end(sql);
  });
}
function dbSysSql(sql) {
  const cloudAdminSql=process.env.DOOMDB_DB_ADMIN_SQL_CLIENT;
  if(cloudAdminSql!==undefined&&cloudAdminSql!=='') {
    const result=spawnSync(cloudAdminSql,['-'],{
      input:sql,encoding:'utf8',stdio:['pipe','pipe','pipe']
    });
    assert.equal(result.status,0,
      `cloud admin database diagnostic failed: ${result.stdout}${result.stderr}`);
    return result.stdout;
  }
  const service=process.env.DOOMDB_DB_COMPOSE_SERVICE??'db';
  const result=spawnSync('docker',[
    'compose','-f',`${repository}compose.yaml`,
    'exec','-T',service,'sqlplus','-s','/','as','sysdba'
  ],{
    input:'whenever sqlerror exit failure rollback\n'
      +'set define off echo off verify off\n'
      +'alter session set container=freepdb1;\n'
      +sql+'\nexit success commit\n',
    encoding:'utf8',stdio:['pipe','pipe','pipe']
  });
  assert.equal(result.status,0,
    `SYS database diagnostic failed: ${result.stdout}${result.stderr}`);
  return result.stdout;
}

async function request(path,body) {
  return fetch(new URL(path, root), {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
  });
}

async function post(path, body, expected = true) {
  const response = await request(path,body);
  if (expected) {
    assert.equal(response.ok, true, `${path} returned HTTP ${response.status}`);
    return response.json();
  }
  assert.equal(response.ok, false, `${path} accepted an invalid capability`);
  return null;
}

function decodeBatchTransport(base64) {
  const encoded=Buffer.from(base64,'base64');
  if(encoded.length>=4
      &&encoded[0]===0x1f&&encoded[1]===0x8b
      &&encoded[2]===0x08&&encoded[3]===0x00) {
    return gunzipSync(encoded);
  }
  return encoded;
}

async function waitForActive(match, capability) {
  const deadline = performance.now() + timeoutMs;
  while (performance.now() < deadline) {
    const status = await post('MATCH_STATUS', {
      p_match: match, p_capability: capability,
    });
    if (status.p_match_state === 'ACTIVE' && status.p_generation >= 1) {
      return status;
    }
    assert.ok(!['FAILED', 'CANCELLED', 'TERMINATED'].includes(
      status.p_match_state), `match became ${status.p_match_state}`);
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.fail('database-frame match did not become ACTIVE');
}

async function waitForFrame(match, capability, afterTic) {
  const deadline = performance.now() + timeoutMs;
  while (performance.now() < deadline) {
    const frame = await post('POLL_MATCH_PIXELS', {
      p_match: match,
      p_player_capability: capability,
      p_after_tic: afterTic,
    });
    if (frame.p_ready === 1) return frame;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail(`database frame after tic ${afterTic} did not arrive`);
}

async function waitForBatch(match, capability, afterTic, maxFrames) {
  const deadline = performance.now() + timeoutMs;
  while (performance.now() < deadline) {
    const batch = await post('POLL_MATCH_PIXEL_BATCH', {
      p_match: match,
      p_player_capability: capability,
      p_after_tic: afterTic,
      p_max_frames: maxFrames,
    });
    if (batch.p_frame_count > 0) return batch;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail(`database frame batch after tic ${afterTic} did not arrive`);
}

async function pixelRecoveryAudit(match) {
  const output=await dbSql(`
set serveroutput on size unlimited
set linesize 32767 trimspool on
declare
  l_generation number;l_probes number;l_status varchar2(16);
begin
  select generation,worker_status into l_generation,l_status
    from doom_match_worker_control
   where match_id='${match}'
     and generation=(select generation from doom_match where match_id='${match}');
  select count(*) into l_probes from doom_match_liveness_probe
   where match_id='${match}' and endpoint='PIXEL_POLL';
  dbms_output.put_line('PMLE_PIXEL_AUTH_AUDIT|generation='||l_generation||
    '|status='||l_status||'|probes='||l_probes);
end;
/
`);
  const match_=output.match(
    /PMLE_PIXEL_AUTH_AUDIT\|generation=(\d+)\|status=([A-Z_]+)\|probes=(\d+)/);
  assert.ok(match_,'pixel recovery authorization audit marker missing');
  return {
    generation:Number(match_[1]),status:match_[2],probes:Number(match_[3])
  };
}

async function lifecycleCleanupAudit(match) {
  const output=await dbSql(`
set serveroutput on size unlimited
declare
  l_deadline timestamp with time zone:=systimestamp+numtodsinterval(90,'SECOND');
  l_assigned number;l_active_assignments number;l_ready number;l_polls number:=0;
begin
  loop
    select count(*) into l_assigned from doom_mle_warm_slot
      where assigned_match='${match}';
    select count(*) into l_active_assignments from doom_mle_warm_assignment
      where match_id='${match}' and assignment_status in('PENDING','ACCEPTED');
    select count(*) into l_ready from doom_mle_warm_slot s
      where s.slot_status='READY' and s.assigned_match is null
        and exists(select 1 from user_scheduler_running_jobs r
          where r.job_name=s.job_name and r.session_id=s.worker_sid);
    exit when l_assigned=0 and l_active_assignments=0 and l_ready>=1;
    if systimestamp>=l_deadline then
      raise_application_error(-20000,'retained lifecycle cleanup timeout');
    end if;
    l_polls:=l_polls+1;
    if mod(l_polls,10)=0 then
      doom_worker_lifecycle.reconcile_warm_slots;
    end if;
    dbms_session.sleep(.1);
  end loop;
  dbms_output.put_line('PMLE_LIFECYCLE_CLEANUP|PASS|assigned='||l_assigned||
    '|active_assignments='||l_active_assignments||'|ready='||l_ready);
end;
/
`);
  assert.match(output,
    /PMLE_LIFECYCLE_CLEANUP\|PASS\|assigned=0\|active_assignments=0\|ready=[12]/,
    'retained lifecycle cleanup marker missing');
}

async function assignedSlotAudit(match) {
  const output=await dbSql(`
set heading off feedback off pagesize 0
select 'PMLE_LIVE_FRAME_SLOT|slot='||slot_id
from doom_mle_warm_slot where assigned_match='${match}'
  and slot_status='RUNNING' and assigned_role='AUTHORITY';
`);
  const marker=output.match(/PMLE_LIVE_FRAME_SLOT\|slot=(\d+)/);
  assert.ok(marker,'retained authority slot assignment marker missing');
  const slot=Number(marker[1]);
  if (expectedSlot !== undefined) {
    assert.equal(slot,expectedSlot,'match used the wrong retained slot');
  }
  return slot;
}

async function recoveryFailureAudit(match) {
  return dbSql(`
set heading off feedback off pagesize 0 linesize 32767 trimspool on
select 'PMLE_PIXEL_RECOVERY_DIAGNOSTIC|match_state='||m.match_state
  ||'|match_generation='||m.generation||'|current_tic='||m.current_tic
  ||'|control_generation='||c.generation
  ||'|worker_status='||c.worker_status
  ||'|request_status='||c.request_status
  ||'|job='||c.job_name
  ||'|last_error='||replace(replace(coalesce(c.last_error,'NONE'),'|','/'),
      chr(10),' ')
  from doom_match m join doom_match_worker_control c on c.match_id=m.match_id
 where m.match_id='${match}';
select 'PMLE_PIXEL_RECOVERY_PROBE|generation='||generation
  ||'|session_found='||session_found
  ||'|action='||coalesce(observed_action,'NONE')
  ||'|heartbeat_age_ms='||coalesce(to_char(heartbeat_age_ms),'NULL')
  ||'|decision='||decision
  from doom_match_liveness_probe
 where match_id='${match}'
 order by probe_id;
select 'PMLE_PIXEL_RECOVERY_SLOT|slot='||slot_id
  ||'|status='||slot_status
  ||'|role='||coalesce(assigned_role,'NONE')
  ||'|job='||job_name
  from doom_mle_warm_slot
 order by slot_id;
`);
}

async function readArtifactTuple() {
  const output=await dbSql(`
set serveroutput on size unlimited
declare
  l_authority blob;l_renderer blob;l_coordinator blob;
  l_authority_expected varchar2(64);l_renderer_expected varchar2(64);
  l_coordinator_expected varchar2(64);
  l_authority_sha varchar2(64);l_renderer_sha varchar2(64);
  l_coordinator_sha varchar2(64);
begin
  select source_blob into l_authority from doom_teavm_sim_source;
  select authority_sha256,renderer_source,renderer_sha256,
    coordinator_source,coordinator_sha256
    into l_authority_expected,l_renderer,l_renderer_expected,
      l_coordinator,l_coordinator_expected
    from doom_mle_live_frame_source where artifact_id=1;
  l_authority_sha:=lower(rawtohex(dbms_crypto.hash(
    l_authority,dbms_crypto.hash_sh256)));
  l_renderer_sha:=lower(rawtohex(dbms_crypto.hash(
    l_renderer,dbms_crypto.hash_sh256)));
  l_coordinator_sha:=lower(rawtohex(dbms_crypto.hash(
    l_coordinator,dbms_crypto.hash_sh256)));
  if l_authority_sha<>l_authority_expected
      or l_renderer_sha<>l_renderer_expected
      or l_coordinator_sha<>l_coordinator_expected then
    raise_application_error(-20000,'live-frame artifact SHA mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_LIVE_FRAME_ARTIFACT|authority_sha256='||l_authority_sha||
    '|renderer_sha256='||l_renderer_sha||
    '|coordinator_sha256='||l_coordinator_sha);
end;
/
`);
  const marker=output.replace(/\s+/g,'').match(
    /PMLE_LIVE_FRAME_ARTIFACT\|authority_sha256=([0-9a-f]{64})\|renderer_sha256=([0-9a-f]{64})\|coordinator_sha256=([0-9a-f]{64})/);
  assert.ok(marker,
    'database live-frame sources do not match their staged SHA metadata');
  return {
    authoritySha:marker[1],
    rendererSha:marker[2],
    coordinatorSha:marker[3],
  };
}

const artifacts=await readArtifactTuple();
const created = await post('CREATE_MATCH', {
  p_game_mode: 'COOP', p_skill: 3, p_episode: 1, p_map: 1,
  p_display_name: 'LIVE FRAME E2E', p_max_players: 1,
});
assert.match(created.p_match, /^[0-9a-f]{32}$/);
assert.match(created.p_player_capability, /^[0-9a-f]{64}$/);

let left = false;
let presenceTimer;
try {
  await post('READY_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_ready: 1,
  });
  const active = await waitForActive(
    created.p_match, created.p_player_capability);
  assert.equal(active.p_membership_epoch, 1);
  presenceTimer=setInterval(()=>{
    void post('TOUCH_MATCH_PRESENCE',{
      p_match:created.p_match,
      p_player_capability:created.p_player_capability
    }).catch(()=>{});
  },1_000);

  // Latest-only polling intentionally returns the newest available frame.
  // DMC1 does not serialize presentation-derived animation tables, so a
  // restored tic zero is never published. The first real ticker transition
  // refreshes those tables and publishes tic 1 as the generation seed.
  const seed = await waitForBatch(
    created.p_match, created.p_player_capability, -1, 7);
  assert.ok(seed.p_frame_count>=1&&seed.p_frame_count<=7);
  assert.equal(seed.p_first_tic, 1);
  assert.equal(seed.p_last_tic, seed.p_frame_count);
  assert.equal(seed.p_membership_epoch, active.p_membership_epoch);
  assert.equal(seed.p_generation, active.p_generation);
  const seedBytes = decodeBatchTransport(seed.p_payload);
  assert.equal(seedBytes.subarray(0, 4).toString('ascii'), 'DPB2');
  assert.equal(seedBytes.readUInt32BE(4), seed.p_frame_count);
  assert.equal(seedBytes.length, 8 + seed.p_frame_count*64_008);
  assert.equal(seedBytes.readUInt32BE(8), 1);
  assert.ok(seedBytes.readUInt8(12)>=0&&seedBytes.readUInt8(12)<=13);
  assert.equal(seedBytes.readUInt8(13),1,
    'exact Mocha framebuffer must declare row-major layout');
  assert.deepEqual(seedBytes.subarray(14,16),Buffer.alloc(2));
  const initialBytes=seedBytes.subarray(16,16+64_000);

  // Publication batching is an implementation detail. The interval-3 solo
  // coordinator commits 2/3 synthesized frames with their exact endpoint, so
  // an immediate poll can observe tics 2-4 before 5-7 exist. Prove the six
  // logical records across however many authenticated responses are needed.
  const logicalFrames=[];
  for(let frame=1;frame<seed.p_frame_count;frame+=1) {
    const offset=8+frame*64_008;
    assert.equal(seedBytes.readUInt32BE(offset),frame+1);
    logicalFrames.push(Buffer.from(
      seedBytes.subarray(offset+8,offset+8+64_000)));
  }
  let batchCursor=seed.p_last_tic;
  let initialBatchRequests=0;
  while(batchCursor<7) {
    const batch=await waitForBatch(
      created.p_match,created.p_player_capability,batchCursor,7-batchCursor);
    initialBatchRequests+=1;
    assert.equal(batch.p_first_tic,batchCursor+1);
    assert.equal(batch.p_last_tic,
      batch.p_first_tic+batch.p_frame_count-1);
    assert.equal(batch.p_membership_epoch,active.p_membership_epoch);
    assert.equal(batch.p_generation,active.p_generation);
    const batchBytes=decodeBatchTransport(batch.p_payload);
    assert.equal(batchBytes.subarray(0,4).toString('ascii'),'DPB2');
    assert.equal(batchBytes.readUInt32BE(4),batch.p_frame_count);
    assert.equal(batchBytes.length,8+batch.p_frame_count*64_008);
    for(let frame=0;frame<batch.p_frame_count;frame+=1) {
      const offset=8+frame*64_008;
      const tic=batch.p_first_tic+frame;
      assert.equal(batchBytes.readUInt32BE(offset),tic);
      assert.ok(batchBytes.readUInt8(offset+4)>=0
        &&batchBytes.readUInt8(offset+4)<=13);
      assert.equal(batchBytes.readUInt8(offset+5),1,
        'exact Mocha framebuffer must declare row-major layout');
      assert.deepEqual(batchBytes.subarray(offset+6,offset+8),Buffer.alloc(2));
      logicalFrames.push(Buffer.from(
        batchBytes.subarray(offset+8,offset+8+64_000)));
    }
    batchCursor=batch.p_last_tic;
  }
  assert.equal(logicalFrames.length,6);
  const ticTwoBytes=logicalFrames[0];
  assert.equal(initialBytes.length, 64_000);
  assert.equal(ticTwoBytes.length, 64_000);
  assert.ok(logicalFrames.some(frame=>!frame.equals(initialBytes)),
    'database framebuffer did not change across the first seven tics');

  const inputFrontier = await post('MATCH_STATUS', {
    p_match: created.p_match,
    p_capability: created.p_player_capability,
  });
  assert.equal(inputFrontier.p_match_state, 'ACTIVE');
  assert.equal(inputFrontier.p_generation, active.p_generation);
  const targetTic=Number(inputFrontier.p_current_tic)+8;
  const input = await post('REVISE_MATCH_INPUT', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
    p_input_seq: 1,
    p_ticcmd_hex: '0800000000000000',
    p_target_tic: targetTic,
  });
  assert.equal(input.p_accepted, 1);
  assert.equal(input.p_membership_epoch, active.p_membership_epoch);
  assert.equal(input.p_generation, active.p_generation);
  assert.ok(input.p_effective_tic>=targetTic,
    'movement input effective tic preceded its requested target');

  const movementTic=input.p_effective_tic;
  const beforeMoved = await waitForBatch(
    created.p_match,created.p_player_capability,movementTic-2,1);
  assert.equal(beforeMoved.p_frame_count,1);
  assert.equal(beforeMoved.p_first_tic,movementTic-1);
  const beforeMovedPayload=decodeBatchTransport(beforeMoved.p_payload);
  assert.equal(beforeMovedPayload.readUInt32BE(8),movementTic-1);
  const beforeMovedBytes=beforeMovedPayload.subarray(16);
  const moved = await waitForBatch(
    created.p_match,created.p_player_capability,movementTic-1,1);
  assert.equal(moved.p_frame_count,1);
  assert.equal(moved.p_first_tic,movementTic);
  assert.equal(moved.p_last_tic,movementTic);
  assert.equal(moved.p_membership_epoch,active.p_membership_epoch);
  assert.equal(moved.p_generation,active.p_generation);
  const movedPayload=decodeBatchTransport(moved.p_payload);
  assert.equal(movedPayload.length,8+64_008);
  assert.equal(movedPayload.readUInt32BE(8),movementTic);
  const movedBytes=movedPayload.subarray(16);
  let movedChangedPixels=0;
  for(let pixel=0;pixel<movedBytes.length;pixel+=1) {
    if(movedBytes[pixel]!==beforeMovedBytes[pixel])movedChangedPixels+=1;
  }
  assert.ok(movedChangedPixels>=1_000,
    'effective movement tic did not materially change the database framebuffer');
  const initialSha = createHash('sha256').update(initialBytes).digest('hex');
  const movedSha = createHash('sha256').update(movedBytes).digest('hex');
  process.stdout.write(
    `PMLE_LIVE_FRAME_ENDPOINTS|initial_tic=1|requested_tic=${targetTic}`
      + `|moved_tic=${movementTic}|changed_pixels=${movedChangedPixels}`
      + `|initial_sha256=${initialSha}|moved_sha256=${movedSha}\n`);

  // Wallet-backed SQL diagnostics are deliberately behind the admission and
  // movement capture. A managed connection can take many seconds to start;
  // doing this before tic 1 asks a live bounded ring for history after the
  // harness itself allowed that history to expire.
  const assignedSlot=await assignedSlotAudit(created.p_match);
  const invalidBefore=await pixelRecoveryAudit(created.p_match);
  await post('POLL_MATCH_PIXEL_BATCH', {
    p_match: created.p_match,
    p_player_capability: 'f'.repeat(64),
    p_after_tic: 2_147_483_647,
    p_max_frames: 8,
  }, false);
  const invalidAfter=await pixelRecoveryAudit(created.p_match);
  assert.deepEqual(invalidAfter,invalidBefore,
    'invalid capability changed pixel-worker recovery state');

  let batchSoakFrames=0;
  let batchSoakFirstTic=-1;
  let batchSoakLastTic=-1;
  let batchSoakElapsedMs=0;
  if (batchSoakPolls > 0) {
    let soakAfter=moved.p_last_tic;
    const soakStarted=performance.now();
    for (let poll=0;poll<batchSoakPolls;poll+=1) {
      const sample=await waitForBatch(
        created.p_match,created.p_player_capability,soakAfter,8);
      assert.ok(sample.p_frame_count>=1&&sample.p_frame_count<=8);
      assert.equal(sample.p_first_tic,soakAfter+1,
        'progressive DPB2 soak skipped or repeated a frontier');
      assert.equal(sample.p_last_tic,
        sample.p_first_tic+sample.p_frame_count-1);
      const sampleBytes=decodeBatchTransport(sample.p_payload);
      assert.equal(sampleBytes.subarray(0,4).toString('ascii'),'DPB2');
      assert.equal(sampleBytes.readUInt32BE(4),sample.p_frame_count);
      assert.equal(sampleBytes.length,8+sample.p_frame_count*64_008);
      for(let frame=0;frame<sample.p_frame_count;frame+=1) {
        assert.equal(sampleBytes.readUInt32BE(8+frame*64_008),
          sample.p_first_tic+frame);
      }
      if(batchSoakFirstTic<0)batchSoakFirstTic=sample.p_first_tic;
      batchSoakFrames+=sample.p_frame_count;
      batchSoakLastTic=sample.p_last_tic;
      soakAfter=sample.p_last_tic;
    }
    batchSoakElapsedMs=Math.round((performance.now()-soakStarted)*1000)/1000;
    assert.ok(batchSoakFrames>=batchSoakPolls);
    assert.equal(batchSoakLastTic,
      batchSoakFirstTic+batchSoakFrames-1);
  }

  let ringWrapResult='NOT_RUN';
  if(ringWrapMode==='YES') {
    // Force the admission seed to be overwritten in the bounded shared-view
    // ring, then ask from an extinct frontier. Physical slots for the
    // intentionally omitted twentieth tics retain older values; the server
    // must exclude those stale rows and expose a current logical suffix so the
    // confirmed-only client can reset explicitly.
    await waitForFrame(
      created.p_match,created.p_player_capability,389);
    const wrapped=await post('POLL_MATCH_PIXEL_BATCH',{
      p_match:created.p_match,
      p_player_capability:created.p_player_capability,
      p_after_tic:0,p_max_frames:8
    });
    assert.ok(wrapped.p_frame_count>=1&&wrapped.p_frame_count<=8);
    assert.ok(wrapped.p_first_tic>1);
    const wrappedBytes=decodeBatchTransport(wrapped.p_payload);
    assert.equal(wrappedBytes.readUInt32BE(4),wrapped.p_frame_count);
    assert.equal(wrappedBytes.readUInt32BE(8),wrapped.p_first_tic);
    assert.equal(wrappedBytes.length,8+wrapped.p_frame_count*64_008);
    let priorTic=null;
    for(let frame=0;frame<wrapped.p_frame_count;frame+=1) {
      const tic=wrappedBytes.readUInt32BE(8+frame*64_008);
      if(priorTic!==null) {
        const expected=priorTic+((priorTic+1)%20===0?2:1);
        assert.equal(tic,expected,'wrapped DPD1 suffix is not logical');
      }
      priorTic=tic;
    }
    assert.equal(wrapped.p_last_tic,priorTic);
    ringWrapResult='RESET_LOGICAL_SUFFIX';
  }

  let pixelRecoveryResult='NOT_RUN';
  if(recoveryMode==='YES') {
    const incarnation=await dbSql(`
set heading off feedback off pages 0
select 'PMLE_PIXEL_RECOVERY_TARGET|sid='||worker_sid
  ||'|serial='||worker_serial
  from doom_match_worker_control
 where match_id='${created.p_match}' and generation=${active.p_generation}
   and worker_status='READY';
`);
    const target=incarnation.match(
      /PMLE_PIXEL_RECOVERY_TARGET[|]sid=(\d+)[|]serial=(\d+)/);
    assert.ok(target,'pixel recovery worker incarnation is unavailable');
    const killOutput=dbSysSql(`
begin
  execute immediate
    'alter system kill session ''${target[1]},${target[2]}'' immediate';
exception
  when others then
    if sqlcode <> -31 then raise; end if;
end;
/
select 'PMLE_PIXEL_RECOVERY_KILL|PASS|generation=${active.p_generation}'
  from dual;
`);
    assert.match(killOutput,
      new RegExp(`PMLE_PIXEL_RECOVERY_KILL[|]PASS[|]generation=`
        +`${active.p_generation}`));
    let recoveryAfter=moved.p_last_tic;
    let recovered=null;
    const recoveryDeadline=performance.now()+timeoutMs;
    while(performance.now()<recoveryDeadline) {
      const response=await request('POLL_MATCH_PIXEL_BATCH',{
        p_match:created.p_match,
        p_player_capability:created.p_player_capability,
        p_after_tic:recoveryAfter,p_max_frames:8
      });
      if(response.ok) {
        const sample=await response.json();
        if(sample.p_generation===active.p_generation
            &&sample.p_frame_count>0) {
          recoveryAfter=sample.p_last_tic;
        } else if(sample.p_generation>active.p_generation
            &&sample.p_frame_count>0) {
          recovered=sample;break;
        } else if(sample.p_generation>active.p_generation) {
          // Match the production client's generation reset: the new ring is
          // self-contained and its first retained frame becomes the frontier.
          recoveryAfter=-1;
        }
      } else {
        // ORDS exposes the stable capacity error as 429 or 555 depending on
        // the deployment mapping while tier-2/3 recovery is in progress.
        assert.ok([429,500,555].includes(response.status),
          `pixel recovery returned HTTP ${response.status}`);
      }
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    if(recovered===null) {
      process.stderr.write(await recoveryFailureAudit(created.p_match));
    }
    assert.ok(recovered,'pixel polling did not recover the retained authority');
    assert.equal(recovered.p_generation,active.p_generation+1);
    assert.ok(recovered.p_frame_count>=1&&recovered.p_frame_count<=8);
    const recoveredBytes=decodeBatchTransport(recovered.p_payload);
    assert.equal(recoveredBytes.subarray(0,4).toString('ascii'),'DPB2');
    assert.equal(recoveredBytes.readUInt32BE(4),recovered.p_frame_count);
    pixelRecoveryResult=`GENERATION_${recovered.p_generation}`;
    process.stdout.write(
      `PMLE_PIXEL_RECOVERY|PASS|from_generation=${active.p_generation}`
        + `|to_generation=${recovered.p_generation}`
        + `|first_tic=${recovered.p_first_tic}`
        + `|last_tic=${recovered.p_last_tic}\n`);
  }

  const result = await post('LEAVE_MATCH', {
    p_match: created.p_match,
    p_player_capability: created.p_player_capability,
  });
  assert.ok(['FINISHED', 'CANCELLED', 'TERMINATED'].includes(
    result.p_match_state));
  left = true;
  await lifecycleCleanupAudit(created.p_match);

  if (captureDir !== undefined && captureDir !== '') {
    mkdirSync(captureDir,{recursive:true});
    writeFileSync(`${captureDir}/initial-${initialSha}.bin`,initialBytes);
    writeFileSync(`${captureDir}/moved-${movedSha}.bin`,movedBytes);
  }
  assert.match(initialSha,/^[0-9a-f]{64}$/);
  assert.match(movedSha,/^[0-9a-f]{64}$/);
  assert.notEqual(movedSha,initialSha,
    'moving database framebuffer repeated the initial framebuffer');
  process.stdout.write(
    `PMLE_LIVE_FRAME_E2E|PASS|match=REDACTED|initial_tic=1`
      + `|requested_tic=${targetTic}|moved_tic=${movementTic}`
      + `|moved_changed_pixels=${movedChangedPixels}`
      + `|bytes=64000|initial_sha256=${initialSha}|moved_sha256=${movedSha}`
      + `|generation=${active.p_generation}`
      + `|membership_epoch=${active.p_membership_epoch}`
      + `|retained_slot=${assignedSlot}`
      + `|authority_sha256=${artifacts.authoritySha}`
      + `|renderer_sha256=${artifacts.rendererSha}`
      + `|coordinator_sha256=${artifacts.coordinatorSha}`
      + `|batch=DPB2x6|batch_requests=${initialBatchRequests}`
      + `|batch_soak_polls=${batchSoakPolls}`
      + `|batch_soak_frames=${batchSoakFrames}`
      + `|batch_soak_first_tic=${batchSoakFirstTic}`
      + `|batch_soak_last_tic=${batchSoakLastTic}`
      + `|batch_soak_elapsed_ms=${batchSoakElapsedMs}`
      + `|ring_wrap=${ringWrapResult}`
      + `|pixel_recovery=${pixelRecoveryResult}`
      + '|lifecycle_cleanup=PASS'
      + '|invalid_capability=REJECTED\n');
} finally {
  clearInterval(presenceTimer);
  if (!left) {
    try {
      await post('LEAVE_MATCH', {
        p_match: created.p_match,
        p_player_capability: created.p_player_capability,
      });
    } catch {
      // Preserve the primary assertion failure.
    }
  }
}
