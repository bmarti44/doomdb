#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {decodeIndexedPng,encodeIndexedPng} from '../evaluator/t4.3/reference.mjs';

const root=path.resolve(import.meta.dirname,'..');
const out=process.env.DOOMDB_T53_ARTIFACT_DIR
  ?? path.join(root,'artifacts/t5.3-review');
const poses=[
  {id:'spawn-east',x:-416,y:256,angle:0},
  {id:'diagnostic-north',x:-384,y:256,angle:90},
  {id:'diagnostic-south',x:-416,y:320,angle:270},
];

function sql(text,maxBuffer=48*1024*1024){
  const run=spawnSync(path.join(root,'scripts/db_sql.sh'),['-'],{
    cwd:root,input:text,encoding:'utf8',maxBuffer,env:process.env,
  });
  if(run.status!==0){
    process.stderr.write(run.stdout??'');process.stderr.write(run.stderr??'');
    process.exit(run.status??1);
  }
  return run.stdout.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
}

const token='53535353535353535353535353535354';
sql(`set constraints all deferred;
delete from game_sessions where session_token='${token}';
insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
  map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
  last_command_seq,expires_at,created_at)
values('${token}','GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T53REVIEW',0,
  systimestamp+interval '1' hour,systimestamp);
insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
  momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
  yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
  weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
  power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
select '${token}',0,t.x,t.y,0,0,0,0,t.angle,41,0,100,0,0,
  0,0,0,50,0,0,0,3,'PISTOL',0,0,0,0,0,0,0,1
from doom_map_thing t
where t.thing_type=1 and rownum=1;
update game_sessions set current_player_id=0 where session_token='${token}';
insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
  light_level,light_timer,secret_found,damage_clock)
select '${token}',sector_id,floor_height,ceiling_height,light_level,null,0,0
from doom_map_sector;
insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
  momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
  target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id)
select '${token}',thing.thing_id,thing.thing_type,type_def.spawn_state_id,
  state_def.tics,thing.x,thing.y,0,0,0,0,thing.angle,
  coalesce(type_def.radius,0),coalesce(type_def.height,0),
  coalesce(type_def.spawn_health,1),type_def.flags,null,null,0,thing.thing_id,
  null
from doom_map_thing thing
join doom_thing_type_def type_def on type_def.thing_type=thing.thing_type
join doom_state_def state_def on state_def.state_id=type_def.spawn_state_id
where thing.thing_type<>1 and type_def.spawn_state_id is not null;
commit;
`);

try{
  fs.mkdirSync(out,{recursive:true});
  for(const old of fs.readdirSync(out))
    if(/\.(?:png|json)$/.test(old))fs.rmSync(path.join(out,old));
  const summary=[];
  for(const pose of poses){
    const lines=sql(`set feedback off heading off pagesize 0 linesize 32767 trimspool on
update players set x=${pose.x},y=${pose.y},angle=${pose.angle}
 where session_token='${token}' and player_id=0;
commit;
select 'P|'||palette_index||'|'||red||'|'||green||'|'||blue
 from doom_palette_texel order by palette_index;
select 'X|'||world.column_no||'|'||world.row_no||'|'||
       coalesce(masked.palette_index,world.palette_index)||'|'||
       coalesce(masked.source_kind,'WORLD')||'|'||
       coalesce(to_char(masked.source_id),'-')||'|'||
       coalesce(masked.asset_name,'-')
from table(doom_r2_pixels('${token}')) world
left join table(doom_r2_masked_pixels('${token}')) masked
  on masked.column_no=world.column_no and masked.row_no=world.row_no
order by world.column_no,world.row_no;
`,64*1024*1024);
    const palette=lines.filter(line=>line.startsWith('P|'))
      .map(line=>line.split('|').slice(1).map(Number));
    const pixels=lines.filter(line=>line.startsWith('X|'))
      .map(line=>line.split('|').slice(1));
    if(palette.length!==256||pixels.length!==64000)
      throw new Error(`${pose.id}: incomplete database frame`);
    if(!pixels.every((row,i)=>Number(row[0])===Math.floor(i/200)
      && Number(row[1])===i%200))throw new Error(`${pose.id}: noncanonical order`);
    const bytes=Buffer.from(pixels.map(row=>Number(row[2])));
    const png=encodeIndexedPng(bytes,palette.map(row=>row.slice(1)));
    if(!decodeIndexedPng(png).pixels.equals(bytes))
      throw new Error(`${pose.id}: independent PNG round trip failed`);
    const overlays=pixels.filter(row=>row[3]!=='WORLD');
    const sources=[...new Set(overlays.map(row=>`${row[3]}:${row[4]}:${row[5]}`))]
      .sort();
    const frameSha256=crypto.createHash('sha256').update(bytes).digest('hex');
    const pngSha256=crypto.createHash('sha256').update(png).digest('hex');
    const observation={schema:1,kind:'doomdb-r2-masked-diagnostic',
      reviewStatus:'pending-independent-visual-review',width:320,height:200,
      order:'column-row',pose,frameSha256,pngSha256,
      overlayPixelCount:overlays.length,overlaySources:sources};
    fs.writeFileSync(path.join(out,`${pose.id}.png`),png);
    fs.writeFileSync(path.join(out,`${pose.id}.json`),
      `${JSON.stringify(observation,null,2)}\n`);
    summary.push(observation);
    process.stdout.write(`CAPTURE ${pose.id} ${overlays.length} overlay pixels `+
      `${frameSha256}\n`);
  }
  fs.writeFileSync(path.join(out,'review-summary.json'),
    `${JSON.stringify({schema:1,manifest:
      'f8a7ba0189f3c55446d850cd4d2fa5604e16b1ae426015e5ada2729f97ac12ed',
      status:'pending-independent-visual-review',poses:summary},null,2)}\n`);
  process.stdout.write(`PASS T5.3-ACTUAL-ARTIFACTS (${summary.length}/3 database frames)\n`);
}finally{
  sql(`delete from game_sessions where session_token='${token}';\ncommit;\n`);
}
