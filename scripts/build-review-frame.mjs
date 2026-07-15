#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=path.resolve(import.meta.dirname,'..');
const token='d00fd00fd00fd00fd00fd00fd00fd00f';
const sql=`set feedback off heading off pagesize 0 linesize 32767 trimspool on
set constraints all deferred;
declare
  l_weapon doom_weapon_def.weapon_id%type;
  l_x number; l_y number; l_angle number;
begin
  delete from game_sessions where session_token='${token}';
  select min(weapon_id) into l_weapon from doom_weapon_def;
  select x,y,angle into l_x,l_y,l_angle from doom_map_thing
   where thing_id=(select min(thing_id) from doom_map_thing where thing_type=1);
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
  values('${token}','GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'DASHFRAME',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values('${token}',0,l_x,l_y,0,0,0,0,l_angle,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token='${token}';
end;
/
select 'P|'||palette_index||'|'||red||'|'||green||'|'||blue from doom_palette_texel order by palette_index;
select 'X|'||column_no||'|'||row_no||'|'||palette_index||'|'||layer_ordinal from table(doom_r1_pixels('${token}')) order by column_no,row_no;
select 'S|'||x||'|'||y||'|'||angle from players where session_token='${token}' and player_id=0;
delete from game_sessions where session_token='${token}';
commit;
`;
const run=spawnSync(path.join(root,'scripts/db_sql.sh'),['-'],{
  cwd:root,input:sql,encoding:'utf8',maxBuffer:24*1024*1024,env:process.env,
});
if(run.status!==0){process.stderr.write(run.stdout??'');process.stderr.write(run.stderr??'');process.exit(run.status??1);}
const lines=run.stdout.split(/\r?\n/).map(x=>x.trim());
const palette=lines.filter(x=>x.startsWith('P|')).map(x=>x.split('|').slice(1).map(Number));
const pixels=lines.filter(x=>x.startsWith('X|')).map(x=>x.split('|').slice(1).map(Number));
const spawn=lines.find(x=>x.startsWith('S|'))?.split('|').slice(1).map(Number);
if(palette.length!==256||!palette.every((p,i)=>p[0]===i&&p.slice(1).every(v=>Number.isInteger(v)&&v>=0&&v<=255)))throw new Error('database palette is not dense 0..255 RGB');
if(pixels.length!==64000||!pixels.every((p,i)=>p[0]===Math.floor(i/200)&&p[1]===i%200&&p[2]>=0&&p[2]<=255&&[0,1,10].includes(p[3])))throw new Error('database frame is not canonical 320x200');
if(!spawn||spawn.length!==3)throw new Error('database spawn diagnostic absent');
const bytes=Buffer.from(pixels.map(p=>p[2])),frameSha=crypto.createHash('sha256').update(bytes).digest('hex');
const payload={schema:1,kind:'doomdb-r1-database-frame',width:320,height:200,order:'column-row',frameSha,spawn:{x:spawn[0],y:spawn[1],angle:spawn[2]},palette:palette.map(p=>p.slice(1)),pixels:[...bytes],layers:pixels.map(p=>p[3])};
const out=path.join(root,'client/dist/review/frame.json');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,`${JSON.stringify(payload)}\n`);
process.stdout.write(`PASS dashboard database frame (64000/64000 pixels; sha256 ${frameSha})\n`);
