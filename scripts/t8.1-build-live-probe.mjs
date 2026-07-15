#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {candidateDocuments,partitionCommands} from './t8.1-route-tools.mjs';

const root=path.resolve(import.meta.dirname,'..');
const docs=candidateDocuments(root);
const batches=partitionCommands(docs.rows,docs.milestones,'max4');
const milestones=new Map(docs.milestones.map(row=>[row.seq,row.name]));
const sql=[];
sql.push(`set serveroutput on size unlimited timing on
declare
  l_session varchar2(32);l_payload blob;
  procedure mark(p_name varchar2,p_seq number) is
    l_tic number;l_status varchar2(16);l_rng number;l_x number;l_y number;
    l_angle number;l_health number;l_kills number;l_items number;l_secrets number;
    l_keys varchar2(3);l_movers number;l_events number;l_audio number;
    l_state_sha varchar2(64);l_frame_sha varchar2(64);
  begin
    select current_tic,map_status,rng_cursor into l_tic,l_status,l_rng
      from game_sessions where session_token=l_session;
    select x,y,angle,health,kill_count,item_count,secret_count,
      to_char(blue_key)||to_char(yellow_key)||to_char(red_key)
      into l_x,l_y,l_angle,l_health,l_kills,l_items,l_secrets,l_keys
      from players where session_token=l_session and player_id=0;
    select count(*) into l_movers from active_movers
      where session_token=l_session;
    select count(*) into l_events from game_events
      where session_token=l_session;
    select count(*) into l_audio from audio_events
      where session_token=l_session;
    if p_seq=0 then
      select state_sha,frame_sha into l_state_sha,l_frame_sha from (
        select state_sha,frame_sha from state_history
        where session_token=l_session order by tic desc) where rownum=1;
    else
      select state_sha,frame_sha into l_state_sha,l_frame_sha
        from step_responses where session_token=l_session and last_seq=p_seq;
    end if;
    dbms_output.put_line('T81PROBE|'||p_name||'|'||p_seq||'|'||l_tic||'|'||
      l_x||'|'||l_y||'|'||l_angle||'|'||l_health||'|'||l_kills||'|'||
      l_items||'|'||l_secrets||'|'||l_keys||'|'||l_status||'|'||l_movers||
      '|'||l_events||'|'||l_audio||'|'||l_state_sha||'|'||l_frame_sha);
  end;
begin
  doom_api.new_game(3,l_session,l_payload);
  mark('SPAWN',0);`);
for(const batch of batches){
  const document=JSON.stringify({v:1,commands:batch.commands}).replaceAll("'","''");
  sql.push(`  doom_api.step(l_session,to_clob('${document}'),l_payload);`);
  if(milestones.has(batch.lastSeq))
    sql.push(`  mark('${milestones.get(batch.lastSeq)}',${batch.lastSeq});`);
}
sql.push(`  dbms_output.put_line('T81SESSION|'||l_session);
end;
/
`);
const out=process.argv[2]?path.resolve(process.argv[2]):path.join(root,
  'artifacts/t8.1-live/route-probe.sql');
fs.mkdirSync(path.dirname(out),{recursive:true});
fs.writeFileSync(out,sql.join('\n'));
process.stdout.write(`PASS T8.1-LIVE-PROBE-BUILT (${batches.length} public STEP calls)\n`);
