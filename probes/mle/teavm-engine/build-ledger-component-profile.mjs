#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const route=JSON.parse(fs.readFileSync(new URL(
  '../../../artifacts/t8.1-live/mocha-e1m1-skill3-route.json',import.meta.url)));
const value=name=>process.argv.find(argument=>argument.startsWith(`--${name}=`))
  ?.slice(name.length+3);
const limit=Number(value('limit')??500);
const label=value('label')??'candidate';
assert.ok(Number.isInteger(limit)&&limit>=100&&limit<=route.commandCount);
assert.match(label,/^[a-z0-9][a-z0-9._-]{0,31}$/);
assert.equal(route.skill,3);

let turnHeld=0;
function commandVector(command) {
  const forward=Math.abs(command.forward)>1?command.forward:
    command.forward*(command.run?50:25);
  const side=Math.abs(command.strafe)>1?command.strafe:
    command.strafe*(command.run?40:24);
  const mouseTurn=Math.abs(command.turn)>1;
  if(command.turn===0||mouseTurn) turnHeld=0;
  else turnHeld+=1;
  const magnitude=mouseTurn?Math.abs(command.turn)*256:
    turnHeld<6?320:(command.run?1280:640);
  const turn=command.turn===0?0:-Math.sign(command.turn)*magnitude;
  let buttons=(command.fire?1:0)|(command.use?2:0)|
    (command.weapon>0?4|((command.weapon-1)<<3):0);
  if(command.pause) buttons=129;
  const consistency=(command.automap?2:0)|
    (command.menu!=='NONE'?4:0)|(command.cheat?8:0);
  return {forward,side,turn,consistency,buttons};
}

const vectors=route.runs.flatMap(run=>Array.from(
  {length:run.repeat},()=>commandVector(run.command))).slice(0,limit);
const runs=[];
for(const command of vectors) {
  const key=JSON.stringify(command);
  if(runs.at(-1)?.key===key) runs.at(-1).repeat+=1;
  else runs.push({key,command,repeat:1});
}

process.stdout.write(`whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_limit constant pls_integer:=${limit};
  c_label constant varchar2(32):='${label}';
  type values_t is table of number index by pls_integer;
  l_step values_t;l_material values_t;l_export values_t;l_hash values_t;
  l_combined values_t;
  l_tic pls_integer:=0;l_mle_tic number;l_status varchar2(32767);
  l_wad blob;l_pack blob;l_blob blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_started timestamp with time zone;l_all_started timestamp with time zone;
  l_state_sha raw(32);l_digest raw(32):=hextoraw(rpad('0',64,'0'));

  function elapsed_ms(
    p_started timestamp with time zone,p_ended timestamp with time zone
  ) return number is
    l_value interval day to second:=p_ended-p_started;
  begin
    return extract(day from l_value)*86400000+
      extract(hour from l_value)*3600000+
      extract(minute from l_value)*60000+
      extract(second from l_value)*1000;
  end;

  procedure sort_values(p_values in out nocopy values_t) is
    l_value number;l_at pls_integer;
  begin
    for i in 2..c_limit loop
      l_value:=p_values(i);l_at:=i-1;
      while l_at>=1 and p_values(l_at)>l_value loop
        p_values(l_at+1):=p_values(l_at);l_at:=l_at-1;
      end loop;
      p_values(l_at+1):=l_value;
    end loop;
  end;

  procedure profile_one(
    p_forward number,p_side number,p_turn number,p_consistency number,
    p_buttons number
  ) is
    l_step_started timestamp with time zone;l_step_done timestamp with time zone;
    l_material_done timestamp with time zone;l_export_done timestamp with time zone;
    l_hash_done timestamp with time zone;
  begin
    l_tic:=l_tic+1;l_step_started:=systimestamp;
    l_mle_tic:=doom_teavm_sim_step_command(
      p_forward,p_side,p_turn,p_consistency,p_buttons);
    l_step_done:=systimestamp;
    if l_mle_tic<>l_tic then
      raise_application_error(-20796,'component profile frontier '||l_tic);
    end if;
    l_length:=doom_teavm_sim_canonical_length;
    l_material_done:=systimestamp;
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=doom_teavm_sim_canonical_chunk(
        l_offset,least(32767,l_length-l_offset));
      dbms_lob.writeappend(l_blob,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    l_export_done:=systimestamp;
    l_state_sha:=dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256);
    l_digest:=dbms_crypto.hash(utl_raw.concat(
      l_digest,utl_raw.cast_from_binary_integer(l_tic,1),l_state_sha),
      dbms_crypto.hash_sh256);
    l_hash_done:=systimestamp;
    l_step(l_tic):=elapsed_ms(l_step_started,l_step_done);
    l_material(l_tic):=elapsed_ms(l_step_done,l_material_done);
    l_export(l_tic):=elapsed_ms(l_material_done,l_export_done);
    l_hash(l_tic):=elapsed_ms(l_export_done,l_hash_done);
    l_combined(l_tic):=elapsed_ms(l_step_started,l_hash_done);
    dbms_lob.freetemporary(l_blob);
    if mod(l_tic,100)=0 then
      dbms_output.put_line('PMLE_LEDGER_COMPONENT_PROGRESS|label='||c_label||
        '|tic='||l_tic||'|cumulative_sha256='||lower(rawtohex(l_digest)));
    end if;
  exception when others then
    if dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;
    raise;
  end;

  procedure profile_run(
    p_repeat number,p_forward number,p_side number,p_turn number,
    p_consistency number,p_buttons number
  ) is
  begin
    for i in 1..p_repeat loop
      profile_one(p_forward,p_side,p_turn,p_consistency,p_buttons);
    end loop;
  end;

  procedure emit_summary(p_name varchar2,p_values in out nocopy values_t) is
    l_total number:=0;
  begin
    for i in 1..c_limit loop l_total:=l_total+p_values(i);end loop;
    sort_values(p_values);
    dbms_output.put_line('PMLE_LEDGER_COMPONENT|label='||c_label||
      '|component='||p_name||'|tics='||c_limit||
      '|total_ms='||round(l_total,3)||
      '|p50_ms='||round(p_values(ceil(c_limit*.50)),3)||
      '|p95_ms='||round(p_values(ceil(c_limit*.95)),3)||
      '|p99_ms='||round(p_values(ceil(c_limit*.99)),3)||
      '|max_ms='||round(p_values(c_limit),3));
  end;
begin
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);
  l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_status:=doom_teavm_sim_initialize;l_all_started:=systimestamp;
`);
for(const {command,repeat} of runs) {
  process.stdout.write(`  profile_run(${repeat},${command.forward},${command.side},`+
    `${command.turn},${command.consistency},${command.buttons});\n`);
}
process.stdout.write(`  if l_tic<>c_limit then
    raise_application_error(-20796,'component profile length '||l_tic);
  end if;
  emit_summary('ticker',l_step);
  emit_summary('canonical_material',l_material);
  emit_summary('raw_export',l_export);
  emit_summary('native_hash',l_hash);
  emit_summary('combined',l_combined);
  dbms_output.put_line('PMLE_LEDGER_COMPONENT_PROFILE|PASS|label='||c_label||
    '|tics='||c_limit||'|wall_ms='||
    round(elapsed_ms(l_all_started,systimestamp),3)||
    '|cumulative_sha256='||lower(rawtohex(l_digest)));
  doom_teavm_sim_release;
exception when others then
  if dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  raise;
end;
/
`);
