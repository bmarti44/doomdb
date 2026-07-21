#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';

const root = path.resolve(import.meta.dirname, '../..');
const compose = path.join(root, 'compose.yaml');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const finite = value => Number.isFinite(value) && value >= 0;

let input = '';
for await (const chunk of process.stdin) input += chunk;
const request = JSON.parse(input);
assert.equal(request.schema, 1);
assert.equal(request.task, 'T12.1');
assert.equal(request.action, 'collect-complete-observations');
assert.match(request.runtimeCorrelation, /^[0-9a-f]{32}$/);
assert.equal(request.expectedFrames, 300);
const base = new URL(process.env.T121_ORDS_BASE_URL);
assert.ok(base.protocol === 'http:' || base.protocol === 'https:');

function sysSql(body) {
  const preamble = `whenever sqlerror exit sql.sqlcode\nset define off echo off verify off feedback off heading off pagesize 0 linesize 32767 trimspool on tab off\nalter session set container=FREEPDB1;\nalter session set nls_numeric_characters='.,';\n`;
  return execFileSync('docker', ['compose', '-f', compose, 'exec', '-T', 'db',
    'sqlplus', '-s', '/ as sysdba'], {cwd: root, input: `${preamble}${body}\nexit\n`,
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
}

function taggedLines(body, prefix) {
  return sysSql(body).split(/\r?\n/).map(line => line.trim())
    .filter(line => line.startsWith(`${prefix}|`)).map(line => line.split('|'));
}

async function post(route, body) {
  const request = target => fetch(target, {method: 'POST',
    headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
    redirect: 'error', signal: AbortSignal.timeout(120_000)});
  let target = new URL(route.toUpperCase(), base.href.endsWith('/') ? base : `${base.href}/`);
  let response = await request(target);
  if (response.status === 404) {
    target = new URL(route, base.href.endsWith('/') ? base : `${base.href}/`);
    response = await request(target);
  }
  assert.equal(response.ok, true, `${route} matrix call failed: ${response.status}`);
  return response.json();
}

function snapshot(prefix) {
  const sql = `
with families(family,needle) as (
  select 'step','%"DOOM_API"."SUBMIT_STEP"%' from dual union all
  select 'frame','%"DOOM_API"."POLL_FRAME"%' from dual union all
  select 'asset','%"DOOM_API"."GET_ASSET"%' from dual
), ranked as (
  select f.family,s.sql_id,s.force_matching_signature,s.parse_calls,s.executions,
    s.version_count,row_number() over(partition by f.family order by s.last_active_time desc) rn
  from families f join v$sqlarea s on upper(s.sql_text) like f.needle
  where s.parsing_schema_name='DOOM' and s.command_type=47
)
select '${prefix}|'||family||'|'||sql_id||'|'||force_matching_signature||'|'||
  parse_calls||'|'||executions||'|'||version_count from ranked where rn=1;
`;
  const rows = taggedLines(sql, prefix);
  assert.equal(rows.length, 3, `${prefix} AutoREST cursor snapshot`);
  return Object.fromEntries(rows.map(([, family, sqlId, signature, parses,
    executions, versions]) => [family, {sqlId, signature,
      parses: Number(parses), executions: Number(executions), versions: Number(versions)}]));
}

function ready(sequence) {
  const rows = taggedLines(`
select 'R|'||count(*) from doom.doom_worker_request q
join doom.doom_worker_result r on r.request_id=q.request_id
where q.session_token='${request.runtimeCorrelation}'
  and q.expected_command_seq=${sequence - 1} and q.request_status='COMMITTED';`, 'R');
  return rows.length === 1 && Number(rows[0][1]) === 1;
}

async function waitReady(sequence) {
  const deadline = Date.now() + 30_000;
  while (!ready(sequence)) {
    assert.ok(Date.now() < deadline, `matrix sequence ${sequence} did not commit`);
    await delay(25);
  }
}

async function matrixCall(sequence) {
  const command = {seq: sequence, turn: 0, forward: 0, strafe: 0, run: 0,
    fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''};
  const submitted = await post('submit_step', {p_session: request.runtimeCorrelation,
    p_commands: JSON.stringify({v: 2, commands: [command]})});
  assert.match(submitted.p_request, /^[0-9a-f]{32}$/);
  await waitReady(sequence);
  const frame = await post('poll_frame', {p_session: request.runtimeCorrelation,
    p_seq: sequence, p_wait_ms: 0});
  assert.equal(frame.p_ready, 1);
  const asset = await post('get_asset', {p_asset_name: 'M_DOOM'});
  assert.equal(asset.p_media_type, 'application/x-doom-patch');
}

function stages() {
  const rows = taggedLines(`
select 'S|'||to_char(q.expected_command_seq+1)||'|'||
  to_char((greatest(nvl(x.prepare_us,0),0)+greatest(nvl(x.java_prepare_us,0),0)+greatest(nvl(x.finalize_us,0),0)+greatest(nvl(x.commit_us,0),0))/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.prepare_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.actor_tic_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.render_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.codec_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.blob_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.finalize_us,0),0)/1000,'FM999999990D999999')||'|'||
  to_char(greatest(nvl(x.commit_us,0),0)/1000,'FM999999990D999999')||'|'||
  case when least(nvl(x.prepare_us,0),nvl(x.java_prepare_us,0),nvl(x.actor_tic_us,0),
    nvl(x.render_us,0),nvl(x.codec_us,0),nvl(x.blob_us,0),nvl(x.finalize_us,0),
    nvl(x.commit_us,0))<0 then '1' else '0' end||'|'||
  case when x.commit_us is null then '0' else '1' end
from doom.doom_worker_request q join doom.doom_worker_result x
  on x.request_id=q.request_id
where q.session_token='${request.runtimeCorrelation}'
  and q.expected_command_seq between 0 and 298
order by q.expected_command_seq;`, 'S');
  assert.equal(rows.length, 299, 'primary worker-stage rows');
  const zero = {frame: 0, databaseMs: 0, ordsMs: 0, prepareMs: 0,
    tickerMs: 0, renderMs: 0, codecMs: 0, blobMs: 0, finalizeMs: 0,
    commitMs: 0, r1Ms: 0, r2Ms: 0, clockAnomaly: 0, commitSampled: 0};
  return [zero, ...rows.map(([, frame, database, prepare, ticker, render, codec,
    blob, finalize, commit, clockAnomaly, commitSampled]) => {
    const result = {frame: Number(frame), databaseMs: Number(database), ordsMs: 0,
      prepareMs: Number(prepare), tickerMs: Number(ticker), renderMs: Number(render),
      codecMs: Number(codec), blobMs: Number(blob), finalizeMs: Number(finalize),
      commitMs: Number(commit), clockAnomaly: Number(clockAnomaly),
      commitSampled: Number(commitSampled)};
    result.r1Ms = result.tickerMs;
    result.r2Ms = result.renderMs + result.codecMs + result.blobMs;
    assert.ok(Object.values(result).every(finite), `invalid stage ${frame}`);
    return result;
  })];
}

function plans(before, after) {
  const planRows = taggedLines(`
with anchors(family,needle) as (
  select 'step','INSERT INTO DOOM_WORKER_REQUEST(REQUEST_ID,WORKER_SLOT,SESSION_TOKEN,%' from dual union all
  select 'frame','SELECT X.RESPONSE_BLOB FROM DOOM_WORKER_REQUEST Q JOIN DOOM_WORKER_RESULT X%' from dual union all
  select 'asset','SELECT B.ENCODED_BYTES,B.MEDIA_TYPE FROM DOOM_ASSET A JOIN DOOM_ASSET_BLOB B%' from dual
), cursors as (
  select a.family,s.sql_id,s.child_number,s.plan_hash_value,
    row_number() over(partition by a.family order by s.last_active_time desc,s.child_number desc) rn
  from anchors a join v$sql s on upper(s.sql_text) like a.needle
  where s.parsing_schema_name='DOOM' and exists(select 1 from v$sql_plan_statistics_all p
    where p.sql_id=s.sql_id and p.child_number=s.child_number)
)
select 'P|'||c.family||'|'||c.sql_id||'|'||c.plan_hash_value||'|'||p.id||'|'||
  replace(nvl(p.operation,'UNKNOWN'),'|','/')||' '||replace(nvl(p.options,''),'|','/')||'|'||
  nvl(p.last_starts,0)||'|'||nvl(p.last_output_rows,0)||'|'||nvl(p.last_elapsed_time,0)
from cursors c join v$sql_plan_statistics_all p
  on p.sql_id=c.sql_id and p.child_number=c.child_number
where c.rn=1 order by c.family,p.id;`, 'P');
  const grouped = Object.fromEntries(request.families.map(family => [family, []]));
  const identities = {};
  for (const [, family, sqlId, planHash, id, operation, starts, rows, elapsed] of planRows) {
    identities[family] = sqlId;
    grouped[family].push({id: Number(id), operation, starts: Number(starts),
      aRows: Number(rows), elapsedUs: Number(elapsed)});
  }
  return request.families.map(family => {
    assert.ok(grouped[family].length > 0, `${family} anchor plan missing`);
    return {family, format: 'ALLSTATS LAST',
      planHashValue: Number(planRows.find(row => row[1] === family)[3]),
      executionsBefore: before[family].executions,
      executionsAfter: after[family].executions,
      operations: grouped[family], anchorSqlIdSha256: sha(identities[family]),
      attribution: 'INTERNAL_PACKAGE_SQL_ANCHOR'};
  });
}

let restored = false;
try {
  sysSql('alter system set statistics_level=all scope=memory;\nalter system flush shared_pool;');
  // One warm call creates the diagnostic children; it is excluded from the
  // exact before/after 90-call matrix.
  await matrixCall(300);
  const before = snapshot('B');
  for (let sequence = 301; sequence <= 390; sequence += 1) await matrixCall(sequence);
  const after = snapshot('A');
  for (const family of request.families) {
    assert.equal(after[family].executions - before[family].executions, 90,
      `${family} AutoREST execution delta`);
    assert.ok(after[family].parses - before[family].parses <= 1,
      `${family} hard-parse growth`);
    assert.equal(after[family].versions, 1, `${family} child proliferation`);
  }
  const planRecords = plans(before, after);
  const vsql = request.families.map(family => ({family,
    sqlIdSha256: sha(after[family].sqlId),
    forceMatchingSignature: String(after[family].signature),
    normalizedShape: `AUTOREST_${family.toUpperCase()}(:BIND_SET)`,
    parseCallsBefore: before[family].parses, parseCallsAfter: after[family].parses,
    executionsBefore: before[family].executions,
    executionsAfter: after[family].executions, versionCount: after[family].versions}));
  const shapes = [];
  for (const [familyIndex, family] of request.families.entries()) {
    for (const pose of request.poses) for (const command of request.commands) {
      shapes.push({family, pose, command,
        normalizedShape: `AUTOREST_${family.toUpperCase()}(:BIND_SET)`,
        forceMatchingSignature: String(after[family].signature),
        bindCount: [3, 5, 3][familyIndex]});
    }
  }
  const result = {families: request.families, plans: planRecords, vsql, shapes,
    stageSamples: stages()};
  sysSql('alter system set statistics_level=typical scope=memory;\nalter system flush shared_pool;');
  restored = true;
  process.stdout.write(JSON.stringify(result));
} finally {
  if (!restored) {
    try { sysSql('alter system set statistics_level=typical scope=memory;\nalter system flush shared_pool;'); }
    catch { /* Preserve the original collector failure. */ }
  }
}
