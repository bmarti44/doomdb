#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {decodeIndexedPng,encodeIndexedPng} from '../evaluator/t4.3/reference.mjs';

const root=path.resolve(import.meta.dirname,'..');
const out=process.env.DOOMDB_T54_ARTIFACT_DIR
  ?? path.join(root,'artifacts/t5.4-review');
const token='54545454545454545454545454545455';
const states=[
  {id:'game-pistol',mode:'GAME',paused:0,menu:'NONE',automap:'OFF',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'game-shotgun',mode:'GAME',paused:0,menu:'NONE',automap:'OFF',
    status:'ACTIVE',weapon:'SHOTGUN',health:100,bullets:50,shells:8,blue:0},
  {id:'game-paused',mode:'GAME',paused:1,menu:'NONE',automap:'OFF',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'menu-selection-0',mode:'MENU',paused:0,menu:'0',automap:'OFF',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'menu-selection-2',mode:'MENU',paused:0,menu:'2',automap:'OFF',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'automap-normal',mode:'AUTOMAP',paused:0,menu:'NONE',automap:'ON',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'automap-full',mode:'AUTOMAP',paused:0,menu:'NONE',automap:'FULL',
    status:'ACTIVE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'intermission',mode:'INTERMISSION',paused:0,menu:'NONE',automap:'OFF',
    status:'COMPLETE',weapon:'PISTOL',health:100,bullets:50,shells:8,blue:0},
  {id:'hud-hidden-values',mode:'GAME',paused:0,menu:'NONE',automap:'OFF',
    status:'ACTIVE',weapon:'PISTOL',health:37,bullets:9,shells:8,blue:1},
];

function sql(text,maxBuffer=64*1024*1024){
  const run=spawnSync(path.join(root,'scripts/db_sql.sh'),['-'],{
    cwd:root,input:text,encoding:'utf8',maxBuffer,env:process.env,
  });
  if(run.status!==0){
    process.stderr.write(run.stdout??'');process.stderr.write(run.stderr??'');
    process.exit(run.status??1);
  }
  return run.stdout.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
}

sql(`set constraints all deferred;
delete from game_sessions where session_token='${token}';
insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
  map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
  last_command_seq,expires_at,created_at)
values('${token}','GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T54REVIEW',0,
  systimestamp+interval '1' hour,systimestamp);
insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
  momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
  yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
  weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
  power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
values('${token}',0,-416,256,0,0,0,0,0,41,0,100,25,1,0,0,0,
  50,8,2,40,7,'PISTOL',0,0,0,0,12,4,1,1);
update game_sessions set current_player_id=0 where session_token='${token}';
commit;
`);

try{
  fs.mkdirSync(out,{recursive:true});
  for(const old of fs.readdirSync(out))
    if(/\.(?:png|json)$/.test(old))fs.rmSync(path.join(out,old));
  const summary=[];
  for(const state of states){
    const lines=sql(`set feedback off heading off pagesize 0 linesize 32767 trimspool on
update game_sessions set game_mode='${state.mode}',paused=${state.paused},
  menu_state='${state.menu}',automap_state='${state.automap}',
  map_status='${state.status}' where session_token='${token}';
update players set selected_weapon='${state.weapon}',health=${state.health},
  ammo_bullets=${state.bullets},ammo_shells=${state.shells},
  blue_key=${state.blue} where session_token='${token}' and player_id=0;
commit;
select 'P|'||palette_index||'|'||red||'|'||green||'|'||blue
 from doom_palette_texel order by palette_index;
select 'X|'||column_no||'|'||row_no||'|'||palette_index||'|'||
       source_kind||'|'||source_id||'|'||layer_ordinal
from table(doom_r2_presentation('${token}'))
order by column_no,row_no;
`,80*1024*1024);
    const palette=lines.filter(line=>line.startsWith('P|'))
      .map(line=>line.split('|').slice(1).map(Number));
    const pixels=lines.filter(line=>line.startsWith('X|'))
      .map(line=>line.split('|').slice(1));
    if(palette.length!==256||pixels.length!==64000)
      throw new Error(`${state.id}: incomplete database frame`);
    if(!pixels.every((row,i)=>Number(row[0])===Math.floor(i/200)
      && Number(row[1])===i%200))throw new Error(`${state.id}: noncanonical order`);
    const bytes=Buffer.from(pixels.map(row=>Number(row[2])));
    const png=encodeIndexedPng(bytes,palette.map(row=>row.slice(1)));
    if(!decodeIndexedPng(png).pixels.equals(bytes))
      throw new Error(`${state.id}: independent PNG round trip failed`);
    const sourceCounts={};
    for(const row of pixels)sourceCounts[row[3]]=(sourceCounts[row[3]]??0)+1;
    const observation={schema:1,kind:'doomdb-r2-presentation-diagnostic',
      reviewStatus:'pending-independent-visual-review',width:320,height:200,
      order:'column-row',state,
      frameSha256:crypto.createHash('sha256').update(bytes).digest('hex'),
      pngSha256:crypto.createHash('sha256').update(png).digest('hex'),
      sourceCounts};
    fs.writeFileSync(path.join(out,`${state.id}.png`),png);
    fs.writeFileSync(path.join(out,`${state.id}.json`),
      `${JSON.stringify(observation,null,2)}\n`);
    summary.push(observation);
    process.stdout.write(`CAPTURE ${state.id} ${observation.frameSha256}\n`);
  }
  fs.writeFileSync(path.join(out,'review-summary.json'),
    `${JSON.stringify({schema:1,manifest:
      '77236041e8925fdae418af702f03ca3f7ab314e84b2e11a2dfd4ed733c1cc0ae',
      status:'pending-independent-visual-review',frames:summary},null,2)}\n`);
  process.stdout.write(`PASS T5.4-ACTUAL-ARTIFACTS (${summary.length}/9 database frames)\n`);
}finally{
  sql(`delete from game_sessions where session_token='${token}';\ncommit;\n`);
}
