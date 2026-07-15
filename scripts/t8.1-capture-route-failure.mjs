#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=path.resolve(import.meta.dirname,'..');
const sql=`set heading off feedback off pagesize 0 linesize 32767 trimspool on
select 'M|'||command_seq||'|'||tic||'|'||state_sha||'|'||
 json_value(state_blob,'$.player.x')||'|'||json_value(state_blob,'$.player.y')||'|'||
 json_value(state_blob,'$.player.angle')||'|'||json_value(state_blob,'$.player.health')||'|'||
 json_value(state_blob,'$.player.alive')||'|'||json_value(state_blob,'$.player.kill_count')||'|'||
 json_value(state_blob,'$.player.item_count')||'|'||json_value(state_blob,'$.player.secret_count')||'|'||
 json_value(state_blob,'$.player.blue_key')||json_value(state_blob,'$.player.yellow_key')||json_value(state_blob,'$.player.red_key')
from tic_commands where command_seq in(137,165,(select max(command_seq) from tic_commands))
order by command_seq;
select 'F|'||s.current_tic||'|'||s.last_command_seq||'|'||s.map_status||'|'||
 p.x||'|'||p.y||'|'||p.angle||'|'||p.health||'|'||p.alive||'|'||p.kill_count||'|'||
 p.item_count||'|'||p.secret_count||'|'||p.blue_key||p.yellow_key||p.red_key
from game_sessions s join players p on p.session_token=s.session_token
 and p.player_id=s.current_player_id;
select 'E|'||event_type||'|'||count(*)||'|'||min(tic)||'|'||max(tic)
from game_events group by event_type order by event_type;
`;
const run=spawnSync(path.join(root,'scripts/db_sql.sh'),['-'],{
  cwd:root,input:sql,encoding:'utf8',env:process.env,maxBuffer:4*1024*1024});
if(run.status!==0){process.stderr.write(run.stdout);process.stderr.write(run.stderr);process.exit(run.status??1);}
const lines=run.stdout.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
const milestones=lines.filter(line=>line.startsWith('M|')).map(line=>{
  const [seq,tic,stateSha,x,y,angle,health,alive,kills,items,secrets,keys]=
    line.split('|').slice(1);
  return {seq:Number(seq),tic:Number(tic),stateSha,x:Number(x),y:Number(y),
    angle:Number(angle),health:Number(health),alive:Number(alive),
    kills:Number(kills),items:Number(items),secrets:Number(secrets),keys};
});
const finalParts=lines.find(line=>line.startsWith('F|'))?.split('|').slice(1);
assert.ok(finalParts,'final route row missing');
const [tic,seq,mapStatus,x,y,angle,health,alive,kills,items,secrets,keys]=finalParts;
const events=lines.filter(line=>line.startsWith('E|')).map(line=>{
  const [eventType,count,firstTic,lastTic]=line.split('|').slice(1);
  return {eventType,count:Number(count),firstTic:Number(firstTic),lastTic:Number(lastTic)};
});
const observation={schema:1,task:'T8.1',status:'FAILED_CANDIDATE_NOT_APPROVED',
  manifest:'5d67fa78932123407f390208933cf18bd174604f91bbec73bd43d744d5b665c5',
  route:{commandCount:1393,executedThroughSeq:Number(seq),batchLimit:4},
  failure:{firstIrrecoverableMilestone:'FIRST_RESOURCE',reason:
    'player dead before representative fight; key/door/lift/secret/exit unreachable'},
  milestones,final:{tic:Number(tic),seq:Number(seq),mapStatus,x:Number(x),y:Number(y),
    angle:Number(angle),health:Number(health),alive:Number(alive),kills:Number(kills),
    items:Number(items),secrets:Number(secrets),keys},events,
  frames:{status:'NOT_CAPTURED',reason:
    'semantic probe used diagnostic transport frames; no frame or PNG is acceptance evidence'},
  review:{status:'PENDING_EVALUATOR_ROUTE_CORRECTION',approvedScriptSha:null,
    approvedRouteSummarySha:null,goldenStateFrameHashes:[],screenshotHashes:[]}};
const out=path.join(root,'artifacts/t8.1-live/route-candidate-failure.json');
fs.mkdirSync(path.dirname(out),{recursive:true});
fs.writeFileSync(out,`${JSON.stringify(observation,null,2)}\n`);
process.stdout.write(`FAIL-CLOSED T8.1-CANDIDATE (${observation.route.executedThroughSeq}/1393; `+
  `dead before representative fight; no goldens)\n`);
