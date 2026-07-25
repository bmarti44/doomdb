import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {dirname, resolve} from 'node:path';
import {
  oneDbRecord,
  selfTestDbOutput,
  sqlclWideOutput,
} from '../scripts/lib/db-output.mjs';

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dbSql = resolve(rootDir, 'scripts/db_sql.sh');
const dbContainer = execFileSync('docker', ['compose', 'ps', '-q', 'db'], {
  cwd: rootDir,
  encoding: 'utf8',
}).trim();
assert.ok(dbContainer, 'database container is unavailable');
const apiRoot = new URL(process.env.DOOMDB_ORDS_BASE_URL ??
  'http://localhost:8080/ords/doom/doom_api/');
let restorePool = false;
const selectedScenario = process.env.DOOMDB_ASYNC_RACE_SCENARIO ?? 'ALL';
assert.ok(['ALL', 'CLAIM_STORM', 'LEAVE_STARTING', 'FAILED_STARTING',
  'DISPATCH_DEATH'].includes(selectedScenario));
selfTestDbOutput();

function sql(source, prefix) {
  const output = execFileSync(dbSql, ['-'], {
    cwd: rootDir,
    input: `${sqlclWideOutput}\nwhenever sqlerror exit failure rollback\n${source}\n`,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
  });
  return prefix ? oneDbRecord(output, prefix) : output;
}

function sysSql(source) {
  return execFileSync('docker', [
    'exec', '-i', dbContainer, 'sqlplus', '-s', '/', 'as', 'sysdba',
  ], {
    cwd: rootDir,
    input: `whenever sqlerror exit sql.sqlcode rollback\n`
      + `alter session set container=freepdb1;\n${sqlclWideOutput}\n`
      + `${source}\n`,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
  });
}

function fields(record) {
  return Object.fromEntries(record.split('|').slice(2).map(part => {
    const equals = part.indexOf('=');
    return [part.slice(0, equals), part.slice(equals + 1)];
  }));
}

async function post(path, body, allowError = false) {
  const response = await fetch(new URL(path, apiRoot), {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok && !allowError) {
    throw new Error(`${path} returned HTTP ${response.status}: ${text}`);
  }
  let payload;
  try { payload = JSON.parse(text); } catch { payload = {raw: text}; }
  return {status: response.status, ok: response.ok, payload};
}

async function waitForPoolReady(timeoutMs = 180_000) {
  const deadline = performance.now() + timeoutMs;
  while (performance.now() < deadline) {
    const record = sql(`
select 'PMLE_POOL|STATE|ready='||count(case when slot_status='READY'
  and assigned_match is null then 1 end)||'|busy='||
  count(case when slot_status in('CLAIMED','RUNNING','WARMING') then 1 end)
from doom_mle_warm_slot;`, 'PMLE_POOL|');
    const state = fields(record);
    if (state.ready === '2' && state.busy === '0') return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('timed out waiting for two idle READY retained slots');
}

async function createSolo(label) {
  const {payload} = await post('CREATE_MATCH', {
    p_game_mode: 'COOP',
    p_skill: 3,
    p_episode: 1,
    p_map: 1,
    p_display_name: label,
    p_max_players: 1,
  });
  assert.match(payload.p_match, /^[0-9a-f]{32}$/);
  assert.match(payload.p_player_capability, /^[0-9a-f]{64}$/);
  return {
    match: payload.p_match,
    capability: payload.p_player_capability,
  };
}

async function ready(match) {
  return post('READY_MATCH', {
    p_match: match.match,
    p_player_capability: match.capability,
    p_ready: 1,
  });
}

async function status(match, allowError = false) {
  return post('MATCH_STATUS', {
    p_match: match.match,
    p_capability: match.capability,
  }, allowError);
}

async function leave(match, allowError = true) {
  return post('LEAVE_MATCH', {
    p_match: match.match,
    p_player_capability: match.capability,
  }, allowError);
}

async function waitForState(match, accepted, timeoutMs = 30_000) {
  const deadline = performance.now() + timeoutMs;
  let last;
  while (performance.now() < deadline) {
    last = await status(match, true);
    if (last.ok && accepted.includes(last.payload.p_match_state)) return last.payload;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`timed out waiting for ${accepted.join('/')} (last=${JSON.stringify(last)})`);
}

async function claimStorm() {
  await waitForPoolReady();
  const match = await createSolo('ASYNC CLAIM STORM');
  const readyRequest = ready(match);
  const polls = Array.from({length: 8}, () => status(match, true));
  await Promise.all([readyRequest, ...polls]);
  await waitForState(match, ['ACTIVE']);
  const record = sql(`
select 'PMLE_ASYNC_RACE|STATE|assignments='||assignment_count||
  '|controls='||(select count(*) from doom_match_worker_control
    where match_id='${match.match}')||
  '|generation='||(select generation from doom_match where match_id='${match.match}')
from (select count(*) assignment_count from doom_mle_warm_assignment
  where match_id='${match.match}' and assigned_role='AUTHORITY');`,
  'PMLE_ASYNC_RACE|');
  const state = fields(record);
  assert.equal(state.assignments, '1');
  assert.equal(state.controls, '1');
  assert.equal(state.generation, '1');
  await leave(match);
  process.stdout.write(
    'PMLE_ASYNC_ADMISSION_RACE|PASS|scenario=ready_status_claim_storm|pollers=8|authority_claims=1\n');
}

async function leaveDuringStarting() {
  await waitForPoolReady();
  const match = await createSolo('ASYNC LEAVE STARTING');
  await ready(match);
  const result = await leave(match, false);
  assert.ok(['FINISHED', 'CANCELLED'].includes(result.payload.p_match_state));
  const deadline = performance.now() + 20_000;
  let terminal;
  while (performance.now() < deadline) {
    const record = sql(`
select 'PMLE_ASYNC_RACE|STATE|match_state='||match_state||
  '|active_capacity='||(select count(*) from doom_match
    where match_state in('LOBBY','ACTIVE')
      and expires_at>localtimestamp at time zone 'UTC')
from doom_match where match_id='${match.match}';`, 'PMLE_ASYNC_RACE|');
    terminal = fields(record);
    if (['FINISHED', 'CANCELLED'].includes(terminal.match_state) &&
        terminal.active_capacity === '0') break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(['FINISHED', 'CANCELLED'].includes(terminal?.match_state));
  assert.equal(terminal.active_capacity, '0');
  process.stdout.write(
    `PMLE_ASYNC_ADMISSION_RACE|PASS|scenario=member_leave_during_starting|terminal=${terminal.match_state}|capacity_released=1\n`);
}

async function failedDuringStarting() {
  await waitForPoolReady();
  const match = await createSolo('ASYNC FAILED STARTING');
  await ready(match);
  await waitForState(match, ['ACTIVE']);
  // The real ACTIVE+STARTING publish window is intentionally only one commit
  // wide. Persist its exact state transition deterministically rather than
  // making the gate depend on an ORDS/SQL polling race.
  sql(`
update doom_match set current_tic=0 where match_id='${match.match}'
  and match_state='ACTIVE';
update doom_match_worker_control set worker_status='STARTING',
  request_status='IDLE' where match_id='${match.match}';
commit;
update doom_match_worker_control set worker_status='FAILED',
  request_status='FAILED',last_error='async lifecycle injected STARTING failure'
where match_id='${match.match}' and worker_status='STARTING';
commit;`);
  const terminal = await waitForState(match, ['CANCELLED'], 5000);
  assert.equal(terminal.p_current_tic, 0);
  process.stdout.write(
    'PMLE_ASYNC_ADMISSION_RACE|PASS|scenario=failed_during_starting|terminal=CANCELLED|bounded_ms=5000\n');
}

async function dispatchDeath() {
  await waitForPoolReady();
  const match = await createSolo('ASYNC DISPATCH DEATH');
  await ready(match);
  const assignment = fields(sql(`
select 'PMLE_DISPATCH|STATE|sid='||worker_sid||'|serial='||worker_serial||
  '|slot='||slot_id||'|status='||assignment_status
from doom_mle_warm_assignment where match_id='${match.match}'
  and assigned_role='AUTHORITY' and assignment_status in('PENDING','ACCEPTED');`,
  'PMLE_DISPATCH|'));
  assert.match(assignment.sid, /^[0-9]+$/);
  assert.match(assignment.serial, /^[0-9]+$/);
  restorePool = true;
  sysSql(`
begin
  execute immediate 'alter system kill session ''${assignment.sid},${assignment.serial}'' immediate';
exception when others then
  if sqlcode<>-31 then raise;end if;
end;
/`);
  await new Promise(resolve => setTimeout(resolve, 1200));
  const active = await waitForState(match, ['ACTIVE'], 30_000);
  assert.equal(active.p_generation, 1);
  const claims = fields(sql(`
select 'PMLE_DISPATCH|STATE|failed='||
  count(case when assignment_status='FAILED' then 1 end)||
  '|live='||count(case when assignment_status in('PENDING','ACCEPTED') then 1 end)
from doom_mle_warm_assignment where match_id='${match.match}'
  and assigned_role='AUTHORITY';`, 'PMLE_DISPATCH|'));
  assert.equal(claims.failed, '1');
  assert.equal(claims.live, '1');
  await leave(match);
  process.stdout.write(
    'PMLE_ASYNC_ADMISSION_RACE|PASS|scenario=dispatch_death_before_publish|stale_claim_failed=1|replacement_claim=1\n');
}

try {
  if (['ALL', 'CLAIM_STORM'].includes(selectedScenario)) await claimStorm();
  if (['ALL', 'LEAVE_STARTING'].includes(selectedScenario)) {
    await leaveDuringStarting();
  }
  if (['ALL', 'FAILED_STARTING'].includes(selectedScenario)) {
    await failedDuringStarting();
  }
  if (['ALL', 'DISPATCH_DEATH'].includes(selectedScenario)) {
    await dispatchDeath();
  }
  process.stdout.write(
    `PMLE_ASYNC_ADMISSION_RACES|PASS|scenario_set=${selectedScenario}`
      + `|scenarios=${selectedScenario === 'ALL' ? 4 : 1}`
      + '|db_output_helper=self_tested\n');
} finally {
  // The death cell intentionally consumes one incarnation. Restore the
  // production two-slot pool even when an assertion fails.
  if (restorePool) {
    try {
      sql('begin doom_match_worker.start_warm_pool; end;\n/');
    } catch {}
  }
}
