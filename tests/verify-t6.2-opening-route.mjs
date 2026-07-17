#!/usr/bin/env node
import {spawnSync} from 'node:child_process';

const defaults={turn:0,forward:0,strafe:0,run:0,fire:0,use:0,weapon:0,
  pause:0,automap:0,menu:'NONE',cheat:''};
const commands=[];
const append=(repeat,overrides)=>{
  for(let i=0;i<repeat;i++)commands.push({...defaults,...overrides,
    seq:commands.length+1});
};
for(let step=1;step<=30;step++)commands.push({...defaults,forward:1,
  strafe:step<=8?-1:step<=16?1:-1,run:1,fire:step%5===1?1:0,
  seq:commands.length+1});
append(5,{forward:-1,run:1});
append(8,{turn:-1,fire:1});
append(16,{forward:1,run:1,fire:1});
append(1,{use:1});
append(8,{turn:1,fire:1});
append(8,{forward:1,run:1,fire:1});
append(8,{turn:1,fire:1});
append(14,{forward:1,run:1,fire:1});
append(8,{turn:-1,fire:1});
append(13,{forward:1,run:1,fire:1});
append(12,{fire:1});
append(6,{turn:1,fire:1});
append(20,{fire:1});
append(6,{turn:-1,fire:1});

const batches=[];
for(let at=0;at<commands.length;){
  let width=Math.min(4,commands.length-at);
  for(const boundary of [30,35,58,59,60,76,98,131,163])
    if(commands[at].seq<=boundary&&commands[at].seq+width-1>boundary)
      width=boundary-commands[at].seq+1;
  batches.push(commands.slice(at,at+width));
  at+=width;
}
const q=value=>JSON.stringify(value).replaceAll("'","''");
const calls=batches.map(batch=>{
  const last=batch.at(-1).seq;
  const mark=[30,35,58,59,60,76,98,131,163].includes(last)?
    `\n  mark_(${last});`:'';
  return `  doom_tic_tx.apply_batch(k_token,to_clob('${q({v:1,commands:batch})}'),l_payload);${mark}`;
}).join('\n');
const profile=process.env.DOOMDB_PROFILE_ROUTE==='1';
const profileStart=profile?`
  l_profiler_code:=dbms_profiler.start_profiler(
    'T12.0 moving firing route','163 exact public route commands',l_profiler_run);
  ok(l_profiler_code=0,'route profiler start failed');`:'';
const profileStop=profile?`
  l_profiler_code:=dbms_profiler.stop_profiler;
  ok(l_profiler_code=0,'route profiler stop failed');
  l_profiler_code:=dbms_profiler.flush_data;
  ok(l_profiler_code=0,'route profiler flush failed');
  delete from game_sessions where session_token=k_token;
  commit;
  dbms_output.put_line('ROUTE_PROFILER_RUN|'||l_profiler_run);`:'  rollback;';

const sql=`
set serveroutput on size unlimited
set define off
declare
  k_token constant varchar2(32):='7436326f70656e696e67726f75746531';
  l_payload blob;l_spawn_x number;l_spawn_y number;l_spawn_z number;
  l_spawn_angle number;l_spawn_sector number;
  l_profiler_code binary_integer;l_profiler_run number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20927,p_message);end if;end;
  procedure mark_(p_seq number) is
    l_x number;l_y number;l_health number;l_kills number;l_count number;
  begin
    select x,y,health,kill_count into l_x,l_y,l_health,l_kills
      from players where session_token=k_token and player_id=0;
    if p_seq=30 then
      ok(l_x=48 and l_y=480 and l_health=100 and l_kills=0,
        'public route diverged at medkit opening: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills);
    elsif p_seq=35 then
      ok(l_x=-32 and l_y=480 and l_health=100 and l_kills=0,
        'public route diverged at west stimpack: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills);
    elsif p_seq=58 then
      select count(*) into l_count from game_events where session_token=k_token
        and tic=58 and event_type='LINE_TRIGGER' and number_value=593;
      ok(l_count=1 and l_health=97 and l_kills=0,
        'public route lift trigger diverged: events='||l_count||', health='||l_health||', kills='||l_kills);
    elsif p_seq=59 then
      select count(*) into l_count from active_movers where session_token=k_token;
      ok(abs(l_x-149.01933598375617)<0.000000000001
        and abs(l_y-298.98066401624383)<0.000000000001
        and l_health=97 and l_kills=0 and l_count=1,
        'public route lift crossing diverged: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills||', movers='||l_count);
    elsif p_seq=60 then
      select count(*) into l_count from active_movers where session_token=k_token;
      ok(abs(l_x-149.01933598375617)<0.000000000001
        and abs(l_y-298.98066401624383)<0.000000000001
        and l_health=97 and l_kills=0 and l_count=1,
        'current use/fire command was not visible at sequence 60: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills||', movers='||l_count);
    elsif p_seq=76 then
      select count(*) into l_count from active_movers where session_token=k_token;
      ok(abs(l_x-277.01933598375617)<0.000000000001
        and abs(l_y-298.98066401624383)<0.000000000001
        and l_health=97 and l_kills=1 and l_count=1,
        'public route east lift crossing diverged: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills||', movers='||l_count);
    elsif p_seq=98 then
      ok(abs(l_x-435.4112549695428)<0.000000000001 and l_y=304
        and l_health=94 and l_kills=2,
        'public route diverged at command sequence 98: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills);
    elsif p_seq=131 then
      ok(l_x=640 and l_y=304 and l_health=91 and l_kills=2,
        'public route diverged at command sequence 131: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills);
    elsif p_seq=163 then
      ok(l_x=640 and l_y=304 and l_health=46 and l_kills=3,
        'public route diverged at opening clear: x='||l_x||', y='||l_y||', health='||l_health||', kills='||l_kills);
    end if;
    dbms_output.put_line('T62_ROUTE|'||p_seq||'|'||l_x||'|'||l_y||'|'||
      l_health||'|'||l_kills);
  end;
begin
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T62-OPENING-ROUTE','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  select x,y,angle into l_spawn_x,l_spawn_y,l_spawn_angle
    from doom_map_thing where thing_type=1 and rownum=1;
  select sector_id into l_spawn_sector
    from table(doom_bsp_locate(l_spawn_x,l_spawn_y)) where rownum=1;
  select floor_height into l_spawn_z from doom_map_sector
    where sector_id=l_spawn_sector;
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip)
  values(k_token,0,l_spawn_x,l_spawn_y,l_spawn_z,0,0,0,l_spawn_angle,41,0,100,
    0,0,0,0,0,50,0,0,0,3,'PISTOL',0,0,0,0,0,0,0,1,0);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
    light_level,light_timer,secret_found,damage_clock)
  select k_token,sector_id,floor_height,ceiling_height,light_level,null,0,0
    from doom_map_sector;
  insert into line_state(session_token,linedef_id,trigger_count,switch_on)
  select k_token,linedef_id,0,0 from doom_map_linedef;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id)
  select k_token,t.thing_id,t.thing_type,d.spawn_state_id,s.tics,t.x,t.y,
    0,0,0,0,t.angle,coalesce(d.radius,0),coalesce(d.height,0),
    coalesce(d.spawn_health,1),d.flags,null,null,0,t.thing_id,null
    from doom_map_thing t join doom_thing_type_def d on d.thing_type=t.thing_type
    join doom_state_def s on s.state_id=d.spawn_state_id
   where t.thing_type<>1 and d.spawn_state_id is not null;
${profileStart}
${calls}
${profileStop}
end;
/
`;

const run=spawnSync('scripts/db_sql.sh',['-'],{input:sql,encoding:'utf8',
  env:process.env,maxBuffer:16*1024*1024});
process.stdout.write(run.stdout||'');
process.stderr.write(run.stderr||'');
if(run.status!==0)process.exit(run.status??1);
process.stdout.write('PASS T6.2-OPENING-ROUTE (public prefix semantic equivalence through sequence 163)\n');
