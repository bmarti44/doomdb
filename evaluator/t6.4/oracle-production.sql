whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
  n number; k_token varchar2(32);
  k_weapon varchar2(32); b blob; replay_blob blob; save_sha varchar2(64); uninterrupted_sha varchar2(64); resumed_sha varchar2(64); rewound_sha varchar2(64); replay_id varchar2(128); original_lineage varchar2(64);
  procedure fail(m varchar2) is begin raise_application_error(-20964,m);end;
  procedure ok(v boolean,m varchar2) is begin if not v then fail(m);end if;end;
  function text_of(x blob) return varchar2 is begin return utl_raw.cast_to_varchar2(dbms_lob.substr(x,32767,1));end;
  function field(x blob,p varchar2) return varchar2 is begin return json_value(text_of(x),p returning varchar2);end;
  procedure step_one(seq number,pause number default 0,automap number default 0) is
    c clob;
  begin
    c:='{"v":1,"commands":[{"seq":'||seq||',"turn":0,"forward":0,"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":'||pause||',"automap":'||automap||',"menu":"NONE","cheat":""}]}';
    doom_tic_tx.apply_batch(k_token,c,b);
  end;
begin
  select lower(substr(standard_hash('T64-LIVE-HISTORY','MD5'),1,32)) into k_token from dual;
  select count(*) into n from user_objects where object_name='DOOM_HISTORY' and object_type='PACKAGE' and status='VALID';ok(n=1,'valid DOOM_HISTORY package absent');
  select count(*) into n from user_procedures where object_name='DOOM_HISTORY' and procedure_name in('CAPTURE_TIC','SAVE_GAME','LOAD_GAME','REWIND_TO_TIC','START_REPLAY','STEP_REPLAY');ok(n=6,'history public procedure set absent or overloaded');
  select count(*) into n from user_tables where table_name='REPLAY_CURSORS';ok(n=1,'REPLAY_CURSORS absent');
  select count(*) into n from user_tab_columns where (table_name='TIC_COMMANDS' and column_name in('LINEAGE','PREVIOUS_COMMAND_SHA','STATE_SHA','FRAME_SHA')) or (table_name='GAME_EVENTS' and column_name in('LINEAGE','PREVIOUS_EVENT_SHA','EVENT_SHA')) or (table_name='AUDIO_EVENTS' and column_name in('LINEAGE','PREVIOUS_EVENT_SHA','EVENT_SHA')) or (table_name='STATE_HISTORY' and column_name in('LINEAGE','STATE_SHA','COMMAND_SHA','EVENT_SHA','FRAME_SHA','SNAPSHOT_SHA','SNAPSHOT_REASON'));ok(n=17,'lineage/hash history columns incomplete');
  select count(*) into n from doom_config where config_key='HISTORY_SNAPSHOT_INTERVAL' and number_value=64;ok(n=1,'reviewed snapshot interval absent');
  -- Keep this compact differential fixture at four tics while independently
  -- asserting the selected production cadence above.  The final rollback
  -- restores the session-visible configuration to 64.
  update doom_config set number_value=4 where config_key='HISTORY_SNAPSHOT_INTERVAL';
  select weapon_id into k_weapon from (select weapon_id from doom_weapon_def order by slot_number,weapon_id) where rownum=1;
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at) values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,lower(standard_hash('T64-LINEAGE','SHA256')),0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive) values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,k_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,light_level,secret_found,damage_clock) select k_token,sector_id,floor_height,ceiling_height,light_level,0,0 from doom_map_sector;
  insert into line_state(session_token,linedef_id,trigger_count,switch_on) select k_token,linedef_id,0,0 from doom_map_linedef;
  select save_lineage into original_lineage from game_sessions where session_token=k_token;
  doom_history.save_game(k_token,0,save_sha);ok(regexp_like(save_sha,'^[0-9a-f]{64}$'),'new-game save hash invalid');
  step_one(1);step_one(2);doom_history.save_game(k_token,7,save_sha);
  select count(*) into n from state_history where session_token=k_token and tic=2 and snapshot_reason='SAVE';ok(n=1,'non-interval save checkpoint absent');
  step_one(3,1,0);step_one(4,0,1);uninterrupted_sha:=field(b,'$.state_sha');ok(regexp_like(uninterrupted_sha,'^[0-9a-f]{64}$'),'uninterrupted state hash absent');
  select count(*) into n from state_history where session_token=k_token and tic=4 and snapshot_reason in('INTERVAL','SAVE_INTERVAL');ok(n=1,'fixed interval checkpoint absent');
  doom_history.start_replay(k_token,0,4,replay_id);ok(replay_id is not null,'replay id absent');
  doom_history.load_game(k_token,7,b);ok(field(b,'$.state_sha')=save_sha,'load did not restore saved state hash');
  select count(*) into n from tic_commands where session_token=k_token;ok(n=4,'load rewrote command history');
  select count(distinct lineage) into n from state_history where session_token=k_token;ok(n>=2,'load did not create continuation lineage');
  step_one(5,1,0);step_one(6,0,1);resumed_sha:=field(b,'$.state_sha');ok(resumed_sha=uninterrupted_sha,'save/load continuation state hash diverged');ok(field(b,'$.frame_sha') is not null,'save/load continuation frame hash absent');
  doom_history.rewind_to_tic(k_token,2,b);ok(field(b,'$.state_sha')=save_sha,'rewind did not restore exact tic-two state');
  select count(*) into n from tic_commands where session_token=k_token;ok(n=6,'rewind deleted history');
  step_one(7,1,0);step_one(8,0,1);rewound_sha:=field(b,'$.state_sha');ok(rewound_sha=uninterrupted_sha,'rewind continuation state hash diverged');
  for i in 1..4 loop doom_history.step_replay(replay_id,replay_blob);end loop;
  ok(field(replay_blob,'$.state_sha')=uninterrupted_sha,'new-game replay final state hash diverged');ok(field(replay_blob,'$.frame_sha') is not null,'new-game replay final frame hash absent');ok(field(replay_blob,'$.tic')='4','replay terminal tic drift');
  select count(*) into n from tic_commands where session_token=k_token;ok(n=8,'replay changed append-only commands');
  savepoint before_corruption;
  update tic_commands set command_sha=rpad('0',64,'0') where session_token=k_token and command_seq=8;
  begin
    doom_history.start_replay(k_token,2,4,replay_id);
    doom_history.step_replay(replay_id,replay_blob);doom_history.step_replay(replay_id,replay_blob);
    fail('corrupted command replay succeeded');
  exception when others then if sqlcode=-20964 then raise;end if;end;
  rollback to before_corruption;
  select count(*) into n from tic_commands where session_token=k_token;ok(n=8,'corruption rejection changed history');
  rollback;
  dbms_output.put_line('PASS T6.4-ORACLE-PRODUCTION (save/load, rewind, replay, corruption, append-only continuity)');
end;
/
