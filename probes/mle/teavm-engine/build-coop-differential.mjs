#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const project = new URL('./', import.meta.url);
const environmentSql = fs.readFileSync(new URL('environment-metadata.sql', project), 'utf8');
const artifactSql = fs.readFileSync(new URL('artifact-metadata.sql', project), 'utf8');
const fixture = JSON.parse(fs.readFileSync(new URL(
  '../../../artifacts/p13.3-coop-e1m1-route.json', project)));
const routeUrl = new URL(`../../../${fixture.baseRoute.path}`, project);
const routeBytes = fs.readFileSync(routeUrl);
const route = JSON.parse(routeBytes);
const deepArg = process.argv.find(value => value.startsWith('--deep-every='));
const deepEvery = Number(deepArg?.slice(13) ?? 1);
assert.equal(crypto.createHash('sha256').update(routeBytes).digest('hex'),
  fixture.baseRoute.sha256);
assert.equal(route.commandCount, fixture.commandCount);
assert.equal(route.skill, 1);
assert.ok(Number.isInteger(deepEvery) && deepEvery > 0);

const byte = value => ((value % 256) + 256) % 256;
let turnHeld = 0;
function ticcmd(command) {
  const forward = Math.abs(command.forward) > 1 ? command.forward
    : command.forward * (command.run ? 50 : 25);
  const side = Math.abs(command.strafe) > 1 ? command.strafe
    : command.strafe * (command.run ? 40 : 24);
  const mouseTurn = Math.abs(command.turn) > 1;
  if (command.turn === 0 || mouseTurn) turnHeld = 0;
  else turnHeld += 1;
  const turnMagnitude = mouseTurn ? Math.abs(command.turn) * 256
    : turnHeld < 6 ? 320 : (command.run ? 1280 : 640);
  const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) * turnMagnitude;
  const buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0)
    | (command.weapon > 0 ? 4 | ((command.weapon - 1) << 3) : 0);
  return [byte(forward), byte(side), (turn >> 8) & 255, turn & 255,
    0, 0, 0, buttons];
}

const player0 = route.runs.flatMap(run => Array.from(
  {length: run.repeat}, () => ticcmd(run.command))).slice(0, fixture.commandCount);
for (const transform of fixture.player0Transforms) {
  const axis = transform.axis === 'forward' ? 0 : transform.axis === 'side' ? 1 : -1;
  assert.notEqual(axis, -1);
  for (let tic = transform.firstTic; tic <= transform.lastTic; tic++) {
    player0[tic - 1][axis] = byte(player0[tic - 1][axis] + transform.delta);
  }
}
const player1 = fixture.player1Runs.flatMap(run => Array.from(
  {length: run.lastTic - run.firstTic + 1}, () =>
    Array.from(Buffer.from(run.ticcmdHex, 'hex'))));
assert.equal(player0.length, fixture.commandCount);
assert.equal(player1.length, fixture.commandCount);
const vectors = player0.map((command, index) => Buffer.concat([
  Buffer.from(command), Buffer.from(player1[index])]).toString('hex').toUpperCase());
const runs = [];
for (const vector of vectors) {
  if (runs.at(-1)?.vector === vector) runs.at(-1).repeat++;
  else runs.push({vector, repeat: 1});
}

process.stdout.write(`${environmentSql}
${artifactSql}
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_players constant pls_integer:=2;c_tics constant pls_integer:=${fixture.commandCount};
  c_deep_every constant pls_integer:=${deepEvery};
  l_wad blob;l_pack blob;l_mle_blob blob;l_java_blob blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;l_tic pls_integer:=0;
  l_mle_tic number;l_java varchar2(32767);l_commands raw(16);
  procedure compare_canonical(p_tic number) is
    l_size pls_integer;l_at pls_integer:=0;l_raw raw(32767);
    l_status varchar2(32767);l_mle_sha raw(32);l_java_sha raw(32);
  begin
    dbms_lob.createtemporary(l_mle_blob,true,dbms_lob.call);
    dbms_lob.createtemporary(l_java_blob,true,dbms_lob.call);
    l_size:=doom_teavm_sim_canonical_length;
    while l_at<l_size loop
      l_raw:=doom_teavm_sim_canonical_chunk(l_at,least(32767,l_size-l_at));
      dbms_lob.writeappend(l_mle_blob,utl_raw.length(l_raw),l_raw);
      l_at:=l_at+utl_raw.length(l_raw);
    end loop;
    l_status:=doom_mocha_canonical_blob(l_java_blob);
    if l_status not like 'ok|%' or dbms_lob.getlength(l_java_blob)<>l_size then
      raise_application_error(-20796,'tic '||p_tic||' canonical material failure');end if;
    l_mle_sha:=dbms_crypto.hash(l_mle_blob,dbms_crypto.hash_sh256);
    l_java_sha:=dbms_crypto.hash(l_java_blob,dbms_crypto.hash_sh256);
    if l_mle_sha<>l_java_sha then raise_application_error(-20796,
      'tic '||p_tic||' canonical SHA MLE='||lower(rawtohex(l_mle_sha))||
      ' OJVM='||lower(rawtohex(l_java_sha)));end if;
    dbms_lob.freetemporary(l_mle_blob);dbms_lob.freetemporary(l_java_blob);
  exception when others then
    if dbms_lob.istemporary(l_mle_blob)=1 then dbms_lob.freetemporary(l_mle_blob);end if;
    if dbms_lob.istemporary(l_java_blob)=1 then dbms_lob.freetemporary(l_java_blob);end if;raise;
  end;
  procedure step_run(p_repeat number,p_hex varchar2) is
  begin
    l_commands:=hextoraw(p_hex);
    for n in 1..p_repeat loop
      l_tic:=l_tic+1;l_mle_tic:=doom_teavm_sim_multi_step(c_players,l_commands);
      l_java:=doom_mocha_multiplayer_sim_step(c_players,p_hex);
      if l_mle_tic<>l_tic or l_java not like 'ok|%' then
        raise_application_error(-20795,'tic '||l_tic||' MLE='||l_mle_tic||' OJVM='||l_java);end if;
      if mod(l_tic,c_deep_every)=0 or l_tic=c_tics then compare_canonical(l_tic);end if;
    end loop;
  end;
begin
  l_java:=doom_mocha_dispose;doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_java:=doom_teavm_sim_multi_init_skill(c_players,1);
  l_java:=doom_mocha_multiplayer_sim_init_skill(c_players,1);
  if l_java not like 'ok|%' then raise_application_error(-20795,l_java);end if;
  compare_canonical(0);
`);
for (const run of runs) {
  process.stdout.write(`  step_run(${run.repeat},'${run.vector}');\n`);
}
process.stdout.write(`  if l_tic<>c_tics then raise_application_error(-20797,'route length '||l_tic);end if;
  dbms_output.put_line('PMLE_TEAVM_COOP_DIFFERENTIAL|PASS|players=2|skill=1|tics='||c_tics||
    '|deep_every='||c_deep_every||'|vector_runs=${runs.length}|fixture_sha256=${crypto.createHash('sha256').update(fs.readFileSync(new URL('../../../artifacts/p13.3-coop-e1m1-route.json', project))).digest('hex')}');
  doom_teavm_sim_release;l_java:=doom_mocha_dispose;
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_java:=doom_mocha_dispose;exception when others then null;end;raise;
end;
/
`);
