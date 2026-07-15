whenever sqlerror exit sql.sqlcode rollback
set serveroutput on size unlimited
set define off
declare
  n number;
  k varchar2(32):='73a73a73a73a73a73a73a73a73a73a73';
  z varchar2(64):=rpad('0',64,'0');
  procedure ok(v boolean,m varchar2) is
  begin
    if not v then raise_application_error(-20739,m); end if;
  end;
begin
  select count(*) into n from user_tab_columns
   where table_name='AUDIO_EVENTS' and column_name='SOUND_ID';
  ok(n=0,'legacy sound identity remains');

  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,z,0,
    systimestamp+interval '1' hour,systimestamp);
  insert into game_events(session_token,tic,event_ordinal,event_type)
  values(k,0,0,'MAP_START');
  doom_audio.emit(k,0);

  select count(*) into n from audio_events
   where session_token=k and lineage=z and tic=0 and event_ordinal=0
     and asset_kind='music' and asset_name='D_E1M1'
     and regexp_like(previous_event_sha,'^[0-9a-f]{64}$')
     and regexp_like(event_sha,'^[0-9a-f]{64}$');
  ok(n=1,'music provenance/history row absent');

  select count(*) into n
    from audio_events a
   where a.session_token=k
     and a.event_sha=lower(rawtohex(dbms_crypto.hash(json_object(
       'lineage' value a.lineage,'tic' value a.tic,
       'ordinal' value a.event_ordinal,'asset_kind' value a.asset_kind,
       'asset_name' value a.asset_name,'volume' value a.volume,
       'separation' value a.separation,
       'previous_event_sha' value a.previous_event_sha returning clob),
       dbms_crypto.hash_sh256)));
  ok(n=1,'audio asset provenance hash drift');
  rollback;
  dbms_output.put_line('PASS T7.3-HISTORY-CLOSURE');
end;
/
