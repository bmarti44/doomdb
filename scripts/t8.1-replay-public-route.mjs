#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const container=process.env.DOOMDB_T81_CONTAINER??'doomdb-t81-live-db-1';
const route=JSON.parse(fs.readFileSync(path.join(root,
  'artifacts/t8.1-live/e1m1-public-route.json'),'utf8'));
const terminalTic=route.commandCount;
const checkpointOnly=process.env.DOOMDB_T81_CHECKPOINT_ONLY==='1';
const stopOnDeath=process.env.DOOMDB_T81_STOP_ON_DEATH==='1';
const materializeTic=Number(process.env.DOOMDB_T81_MATERIALIZE_TIC??0);
const materializeSlot=Number(process.env.DOOMDB_T81_MATERIALIZE_SLOT??99);
const resumeSession=process.env.DOOMDB_T81_RESUME_SESSION??'';
const resumeSlot=Number(process.env.DOOMDB_T81_RESUME_SLOT??99);
const startTic=Number(process.env.DOOMDB_T81_START_TIC??0);
const sequenceOffset=Number(process.env.DOOMDB_T81_SEQUENCE_OFFSET??0);
assert.ok(materializeTic===0||Number.isInteger(materializeTic)&&materializeTic>0&&
  materializeTic<terminalTic,'materialize tic');
assert.ok(Number.isInteger(materializeSlot)&&materializeSlot>=0&&materializeSlot<=99,
  'materialize slot');
assert.ok(!resumeSession||/^[0-9a-f]{32}$/.test(resumeSession),'resume session token');
assert.ok(!resumeSession&&startTic===0||resumeSession&&Number.isInteger(startTic)&&
  startTic>0&&startTic<terminalTic,'resume start tic');
assert.ok(Number.isInteger(resumeSlot)&&resumeSlot>=0&&resumeSlot<=99,'resume slot');
assert.ok(Number.isInteger(sequenceOffset)&&sequenceOffset>=0,'sequence offset');
assert.equal(route.runs.reduce((n,run)=>n+run.repeat,0),terminalTic);
const commands=[];
for(const run of route.runs)for(let index=0;index<run.repeat;index++)commands.push(run.command);

function run(command,args,input=null,maxBuffer=32*1024*1024){
  const result=spawnSync(command,args,{cwd:root,input,encoding:'utf8',maxBuffer});
  if(result.status!==0){
    process.stderr.write(result.stdout??'');process.stderr.write(result.stderr??'');
    process.exit(result.status??1);
  }
  return result.stdout;
}
const password=run('docker',['exec',container,'bash','-lc',
  'printf %s "$(</run/secrets/doom_password)"']).trim();
const batches=[];
for(let at=startTic;at<commands.length;){
  let width=Math.min(4,commands.length-at);
  if(at<3543&&at+width>3543)width=3543-at;
  if(materializeTic&&at<materializeTic&&at+width>materializeTic)
    width=materializeTic-at;
  const batch=commands.slice(at,at+width).map((command,index)=>
    ({seq:at+index+1+sequenceOffset,...command}));
  batches.push({last:at+width,json:JSON.stringify({v:1,commands:batch}).replaceAll("'","''")});
  at+=width;
}
const calls=batches.map(batch=>`  doom_tic_tx.apply_batch(l_session,
    to_clob('${batch.json}'),l_payload);${stopOnDeath&&
      (batch.last<=256||batch.last%32===0||batch.last===terminalTic)?`
  select player.alive,player.health,player.x,player.y into l_alive,l_health,l_x,l_y
  from players player join game_sessions session_row
    on session_row.session_token=player.session_token
   and session_row.current_player_id=player.player_id
  where player.session_token=l_session;
  if l_alive=0 then
    raise_application_error(-20010,'uninterrupted route death at tic=${batch.last}'||
      ',health='||l_health||',pos='||l_x||','||l_y);
  end if;`:''}${materializeTic&&batch.last===materializeTic?`
  select player.x,player.y,player.angle,player.health,player.alive,
    player.kill_count,player.item_count,player.secret_count,player.ammo_cells,
    player.ammo_shells into l_x,l_y,l_angle,l_health,l_alive,l_kills,l_items,
    l_secrets,l_cells,l_shells from players player join game_sessions session_row
    on session_row.session_token=player.session_token
   and session_row.current_player_id=player.player_id
    where player.session_token=l_session;
  doom_history.save_game(l_session,${materializeSlot},l_checkpoint_sha);
  commit;
  dbms_output.put_line('PASS T8.1-DIAGNOSTIC-CHECKPOINT|session='||l_session||
    '|slot=${materializeSlot}|tic=${materializeTic}|sha='||l_checkpoint_sha||'|pos='||l_x||','||l_y||
    '|angle='||l_angle||'|health='||l_health||'|alive='||l_alive||
    '|kills='||l_kills||'|items='||l_items||'|secrets='||l_secrets||
    '|cells='||l_cells||'|shells='||l_shells);
  return;`:''}${batch.last===3543?`
  select state_sha into l_checkpoint_sha from tic_commands
    where session_token=l_session and lineage=(select save_lineage from game_sessions
      where session_token=l_session) and tic=3543 and command_ordinal=0;
  select player.x,player.y,player.angle,player.health,player.alive,
    player.kill_count,player.item_count,player.secret_count,player.ammo_cells,
    player.ammo_shells into l_x,l_y,l_angle,l_health,l_alive,l_kills,l_items,
    l_secrets,l_cells,l_shells from players player join game_sessions session_row
    on session_row.session_token=player.session_token
   and session_row.current_player_id=player.player_id
    where player.session_token=l_session;
  dbms_output.put_line('UNINTERRUPTED_CHECKPOINT|session='||l_session||
    '|tic=3543|sha='||l_checkpoint_sha||'|pos='||l_x||','||l_y||
    '|angle='||l_angle||'|health='||l_health||'|alive='||l_alive||
    '|kills='||l_kills||'|items='||l_items||'|secrets='||l_secrets||
    '|cells='||l_cells||'|shells='||l_shells);${checkpointOnly?`
  doom_history.save_game(l_session,99,l_checkpoint_sha);
  commit;
  dbms_output.put_line('PASS T8.1-CORRECTED-CHECKPOINT-MATERIALIZED|session='||
    l_session||'|slot=99|sha='||l_checkpoint_sha);
  return;`:''}`:``}`).join('\n');
const sql=`connect doom/${password}@//localhost:1521/FREEPDB1
set serveroutput on size unlimited
set feedback off heading off pagesize 0 linesize 32767
declare
  l_session varchar2(32);l_payload blob;l_checkpoint_sha varchar2(64);
  l_state_sha varchar2(64);l_mode varchar2(16);l_status varchar2(16);
  l_tic number;l_health number;l_kills number;l_items number;l_secrets number;
  l_x number;l_y number;l_angle number;l_alive number;l_cells number;l_shells number;
  procedure ok(p_condition boolean,p_message varchar2) is
  begin if not p_condition then raise_application_error(-20010,p_message);end if;end;
begin
  ${resumeSession?`l_session:='${resumeSession}';
  doom_history.load_game(l_session,${resumeSlot},l_payload);`:
    'doom_api.new_game(3,l_session,l_payload);'}
${calls}
  select session_row.current_tic,session_row.game_mode,session_row.map_status,
    player.health,player.kill_count,player.item_count,player.secret_count,
    command_row.state_sha
    into l_tic,l_mode,l_status,l_health,l_kills,l_items,l_secrets,l_state_sha
  from game_sessions session_row join players player
    on player.session_token=session_row.session_token
   and player.player_id=session_row.current_player_id
  join tic_commands command_row on command_row.session_token=session_row.session_token
   and command_row.lineage=session_row.save_lineage
   and command_row.tic=session_row.current_tic and command_row.command_ordinal=0
  where session_row.session_token=l_session;
  ok(l_tic=4118 and l_mode='INTERMISSION' and l_status='DONE',
    'terminal mode/status drifted: tic='||l_tic||',mode='||l_mode||
      ',status='||l_status);
  ok(l_health=49 and l_kills=42 and l_items=34 and l_secrets=1,
    'terminal counters drifted: health='||l_health||',kills='||l_kills||
      ',items='||l_items||',secrets='||l_secrets);
  ok(l_state_sha='ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6',
    'terminal SHA drifted: '||l_state_sha);
  dbms_output.put_line('PASS T8.1-UNINTERRUPTED-PUBLIC-REPLAY|tic='||l_tic||
    '|mode='||l_mode||'|status='||l_status||'|health='||l_health||
    '|kills='||l_kills||'|items='||l_items||'|secrets='||l_secrets||
    '|sha='||l_state_sha);
  delete from game_sessions where session_token=l_session;
  commit;
end;
/
exit
`;
const output=run('docker',['exec','-i',container,'sqlplus','-s','/nolog'],sql,64*1024*1024);
process.stdout.write(output);
assert.match(output,materializeTic?/PASS T8\.1-DIAGNOSTIC-CHECKPOINT/:
  checkpointOnly?/PASS T8\.1-CORRECTED-CHECKPOINT-MATERIALIZED/:
    /PASS T8\.1-UNINTERRUPTED-PUBLIC-REPLAY/);
