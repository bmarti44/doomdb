whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
  n number;k varchar2(32):='73333333333333333333333333333333';z varchar2(64):=rpad('0',64,'0');
  procedure ok(v boolean,m varchar2) is begin if not v then raise_application_error(-20730,m);end if;end;
begin
  select count(*) into n from user_objects where object_name='DOOM_AUDIO' and object_type='PACKAGE' and status='VALID';ok(n=1,'valid DOOM_AUDIO absent');
  select count(*) into n from user_procedures where object_name='DOOM_AUDIO' and procedure_name='EMIT';ok(n=1,'unique EMIT absent');
  select count(*) into n from user_tables where table_name='DOOM_AUDIO_EVENT_DEF';ok(n=1,'relational audio definitions absent');
  select count(*) into n from user_tab_columns where table_name='AUDIO_EVENTS' and column_name in('ASSET_KIND','ASSET_NAME');ok(n=2,'asset-kind/name audio event identity absent');
  select count(*) into n from doom_audio_event_def d join doom_asset a on a.asset_kind=d.asset_kind and a.asset_name=d.asset_name where d.event_type in('MAP_START','WEAPON_PISTOL_FIRE','PICKUP','DOOR_OPEN','MONSTER_WAKE','MONSTER_PAIN','MONSTER_DEATH','BARREL_EXPLODE','PLAYER_PAIN');ok(n=9,'reviewed event/asset definition closure absent');
  select count(*) into n from doom_audio_event_def where (event_type='MAP_START' and asset_kind='music' and asset_name='D_E1M1') or(event_type='WEAPON_PISTOL_FIRE' and asset_kind='sound' and asset_name='DSPISTOL')or(event_type='PICKUP' and asset_name='DSITEMUP')or(event_type='DOOR_OPEN' and asset_name='DSDOROPN')or(event_type='MONSTER_WAKE' and asset_name='DSPOSIT1')or(event_type='MONSTER_PAIN' and asset_name='DSPOPAIN')or(event_type='MONSTER_DEATH' and asset_name='DSPODTH1')or(event_type='BARREL_EXPLODE' and asset_name='DSBAREXP')or(event_type='PLAYER_PAIN' and asset_name='DSPLPAIN');ok(n=9,'reviewed mapping drift');
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)values(k,'GAME',3,7,0,'ACTIVE',0,'NONE','OFF',null,z,0,systimestamp+interval '1' hour,systimestamp);
  insert into game_events(session_token,tic,event_ordinal,event_type,actor_mobj_id,target_mobj_id)values(k,7,4,'MONSTER_WAKE',20,1);
  insert into game_events(session_token,tic,event_ordinal,event_type,actor_mobj_id,target_mobj_id)values(k,7,2,'WEAPON_PISTOL_FIRE',1,10);
  insert into game_events(session_token,tic,event_ordinal,event_type,actor_mobj_id,target_mobj_id)values(k,7,3,'PICKUP',1,40);
  insert into game_events(session_token,tic,event_ordinal,event_type)values(k,7,5,'CONTROL_AUTOMAP');
  doom_audio.emit(k,7);
  select count(*) into n from audio_events where session_token=k and tic=7;ok(n=3,'exact three mapped tuples absent');
  select count(*) into n from audio_events where session_token=k and tic=7 and ((event_ordinal=0 and asset_name='DSPISTOL' and volume=255 and separation=128)or(event_ordinal=1 and asset_name='DSITEMUP' and volume=255 and separation=128)or(event_ordinal=2 and asset_name='DSPOSIT1' and volume=220 and separation=80));ok(n=3,'stable dense tuple ordering or mix drift');
  begin doom_audio.emit(k,7);raise_application_error(-20731,'duplicate emit accepted');exception when dup_val_on_index then null;end;
  rollback;select count(*) into n from audio_events where session_token=k;ok(n=0,'rollback retained audio');
  dbms_output.put_line('PASS T7.3-ORACLE-PRODUCTION');
end;
/
