#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const route = JSON.parse(fs.readFileSync(new URL(
  '../../../artifacts/t8.1-live/mocha-e1m1-skill3-route.json', import.meta.url)));
const environmentSql = fs.readFileSync(
  new URL('environment-metadata.sql', import.meta.url), 'utf8');
const artifactSql = fs.readFileSync(
  new URL('artifact-metadata.sql', import.meta.url), 'utf8');
const value = name => process.argv.find(argument => argument.startsWith(`--${name}=`))
  ?.slice(name.length + 3);
const limit = Number(value('limit') ?? route.commandCount);
const deepEvery = Number(value('deep-every') ?? 1);
assert.ok(Number.isInteger(limit) && limit > 0 && limit <= route.commandCount);
assert.ok(Number.isInteger(deepEvery) && deepEvery > 0);
assert.equal(route.skill, 3, 'MLE fixture currently initializes skill 3');

let turnHeld = 0;
function commandVector(command) {
  const forward = Math.abs(command.forward) > 1 ? command.forward
    : command.forward * (command.run ? 50 : 25);
  const side = Math.abs(command.strafe) > 1 ? command.strafe
    : command.strafe * (command.run ? 40 : 24);
  const mouseTurn = Math.abs(command.turn) > 1;
  if (command.turn === 0 || mouseTurn) turnHeld = 0;
  else turnHeld += 1;
  const magnitude = mouseTurn ? Math.abs(command.turn) * 256
    : turnHeld < 6 ? 320 : (command.run ? 1280 : 640);
  const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) * magnitude;
  let buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0)
    | (command.weapon > 0 ? 4 | ((command.weapon - 1) << 3) : 0);
  if (command.pause) buttons = 128 | 1;
  const consistency = (command.automap ? 2 : 0)
    | (command.menu !== 'NONE' ? 4 : 0) | (command.cheat ? 8 : 0);
  return {forward, side, turn, consistency, buttons};
}

const vectors = route.runs.flatMap(run => Array.from(
  {length: run.repeat}, () => commandVector(run.command))).slice(0, limit);
const runs = [];
for (const command of vectors) {
  const key = JSON.stringify(command);
  if (runs.at(-1)?.key === key) runs.at(-1).repeat += 1;
  else runs.push({key, command, repeat: 1});
}

process.stdout.write(`${environmentSql}
${artifactSql}
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_tics constant pls_integer:=${limit};c_deep_every constant pls_integer:=${deepEvery};
  l_wad blob;l_table_pack blob;l_length pls_integer;l_offset pls_integer;l_chunk raw(32767);
  l_loaded number;l_mle_tic number;l_java varchar2(32767);l_tic pls_integer:=0;
  procedure compare_canonical(p_tic number) is
    l_mle_blob blob;l_java_blob blob;l_size pls_integer;l_at pls_integer:=0;
    l_raw raw(32767);l_status varchar2(32767);l_mle_sha raw(32);l_java_sha raw(32);
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
    if l_status not like 'ok|%' then raise_application_error(-20795,l_status);end if;
    if dbms_lob.getlength(l_java_blob)<>l_size then
      raise_application_error(-20796,'tic '||p_tic||' canonical length mismatch');
    end if;
    l_mle_sha:=dbms_crypto.hash(l_mle_blob,dbms_crypto.hash_sh256);
    l_java_sha:=dbms_crypto.hash(l_java_blob,dbms_crypto.hash_sh256);
    if l_mle_sha<>l_java_sha then raise_application_error(-20796,
      'tic '||p_tic||' canonical SHA MLE='||lower(rawtohex(l_mle_sha))||
      ' OJVM='||lower(rawtohex(l_java_sha)));end if;
    dbms_lob.freetemporary(l_mle_blob);dbms_lob.freetemporary(l_java_blob);
  exception when others then
    if dbms_lob.istemporary(l_mle_blob)=1 then dbms_lob.freetemporary(l_mle_blob);end if;
    if dbms_lob.istemporary(l_java_blob)=1 then dbms_lob.freetemporary(l_java_blob);end if;
    raise;
  end;
  procedure step_run(p_repeat number,p_forward number,p_side number,p_turn number,
      p_consistency number,p_buttons number) is
  begin
    for n in 1..p_repeat loop
      l_tic:=l_tic+1;
      l_mle_tic:=doom_teavm_sim_step_command(
        p_forward,p_side,p_turn,p_consistency,p_buttons);
      l_java:=doom_mocha_step_command_simulation(
        p_forward,p_side,p_turn,p_consistency,p_buttons);
      if l_java not like 'ok|%' or l_mle_tic<>l_tic then
        raise_application_error(-20795,'tic '||l_tic||' MLE='||l_mle_tic||' OJVM='||l_java);
      end if;
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
  select table_pack_blob into l_table_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_table_pack);l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_table_pack,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_java:=doom_teavm_sim_initialize;l_java:=doom_mocha_initialize;compare_canonical(0);
`);
for (const {command, repeat} of runs) {
  process.stdout.write(`  step_run(${repeat},${command.forward},${command.side},${command.turn},${command.consistency},${command.buttons});\n`);
}
process.stdout.write(`  if l_tic<>c_tics then raise_application_error(-20797,'ledger length '||l_tic);end if;
  dbms_output.put_line('PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics='||c_tics||
    '|deep_every='||c_deep_every||'|route_runs=${route.runs.length}|vector_runs=${runs.length}');
  doom_teavm_sim_release;l_java:=doom_mocha_dispose;
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_java:=doom_mocha_dispose;exception when others then null;end;
  raise;
end;
/
`);
