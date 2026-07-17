whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  session_ varchar2(32);oracle_session_ varchar2(32);payload_ blob;commands_ clob;
  target_ number;oracle_target_ number;target_health_ number;ammo_ number;refire_ number;
  retained_health_ number;retained_ammo_ number;retained_rng_ number;oracle_health_ number;
  oracle_ammo_ number;oracle_rng_ number;retained_events_ clob;oracle_events_ clob;
  retained_start_rng_ number;oracle_start_rng_ number;
  tic_ number;seq_ number;rng_ number;requests_ number;damage_ number;hits_ number;
  parity_ varchar2(4000);old_enabled_ number;old_parity_ number;
  procedure step_(p_seq number,p_fire number) is
  begin
    commands_:='{"v":1,"commands":[{"seq":'||p_seq||',"turn":0,"forward":0,'||
      '"strafe":0,"run":0,"fire":'||p_fire||',"use":0,"weapon":0,'||
      '"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(session_,commands_,payload_);
    if payload_ is null or dbms_lob.getlength(payload_)=0 then
      raise_application_error(-20000,'empty retained fire frame');
    end if;
  end;
  procedure fixture_(p_session varchar2,p_target out number) is
    x_ number;y_ number;angle_ number;sector_ number;
  begin
    -- Keep the map's live light timers: retained passive world machines must
    -- consume the same ordered RNG prefix before FIRE as the SQL oracle.
    select p.x,p.y,p.angle into x_,y_,angle_ from players p join game_sessions s
      on s.session_token=p.session_token and s.current_player_id=p.player_id
      where p.session_token=p_session;
    select sector_id into sector_ from table(doom_bsp_locate(x_,y_)) where rownum=1;
    delete from mobjs where session_token=p_session and thing_type in(
      select thing_type from doom_thing_type_def where category='barrel');
    update mobjs m set health=0,monster_health_seen=0,death_processed=1,awake=0,state_tics=0
      where m.session_token=p_session and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    update mobjs m set sector_id=(select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1)
      where m.session_token=p_session and m.sector_id is null and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    select min(m.mobj_id) into p_target from mobjs m join doom_monster_def d
      on d.thing_type=m.thing_type where m.session_token=p_session;
    update mobjs m set health=100,monster_health_seen=100,death_processed=0,awake=0,
      x=x_+cos(angle_*acos(-1)/180)*16,y=y_+sin(angle_*acos(-1)/180)*16,sector_id=sector_
      where session_token=p_session and mobj_id=p_target;
  end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop(session_);exception when others then null;end;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    if oracle_session_ is not null then delete from game_sessions where session_token=oracle_session_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';commit;
  doom_api.new_game(3,session_,payload_);
  fixture_(session_,target_);
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';commit;

  select rng_cursor into retained_start_rng_ from game_sessions where session_token=session_;
  step_(1,1);
  select health into retained_health_ from mobjs where session_token=session_ and mobj_id=target_;
  select rng_cursor into retained_rng_ from game_sessions where session_token=session_;
  select ammo_bullets into retained_ammo_ from players where session_token=session_ and
    player_id=(select current_player_id from game_sessions where session_token=session_);
  select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
      number_value,text_value null on null returning varchar2) order by event_ordinal returning clob)
    into retained_events_ from game_events where session_token=session_ and tic=1;

  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';commit;
  doom_api.new_game(3,oracle_session_,payload_);fixture_(oracle_session_,oracle_target_);commit;
  select rng_cursor into oracle_start_rng_ from game_sessions where session_token=oracle_session_;
  commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,"strafe":0,"run":0,'||
    '"fire":1,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
  doom_api.step(oracle_session_,commands_,payload_);
  select health into oracle_health_ from mobjs where session_token=oracle_session_ and mobj_id=oracle_target_;
  select rng_cursor into oracle_rng_ from game_sessions where session_token=oracle_session_;
  select ammo_bullets into oracle_ammo_ from players where session_token=oracle_session_ and
    player_id=(select current_player_id from game_sessions where session_token=oracle_session_);
  select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
      number_value,text_value null on null returning varchar2) order by event_ordinal returning clob)
    into oracle_events_ from game_events where session_token=oracle_session_ and tic=1;
  if retained_health_<>oracle_health_ or retained_rng_<>oracle_rng_ or retained_ammo_<>oracle_ammo_ or
     dbms_lob.compare(retained_events_,oracle_events_)<>0 then
    dbms_output.put_line('FIRE_RETAINED_EVENTS '||dbms_lob.substr(retained_events_,4000,1));
    dbms_output.put_line('FIRE_ORACLE_EVENTS '||dbms_lob.substr(oracle_events_,4000,1));
    dbms_output.put_line('FIRE_START_RNG retained='||retained_start_rng_||' oracle='||oracle_start_rng_);
    raise_application_error(-20000,'retained/SQL fire differential mismatch retained='||
      retained_health_||'/'||retained_rng_||'/'||retained_ammo_||' oracle='||
      oracle_health_||'/'||oracle_rng_||'/'||oracle_ammo_);
  end if;
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';commit;
  step_(2,0);
  select current_tic,last_command_seq,rng_cursor into tic_,seq_,rng_ from game_sessions
    where session_token=session_;
  select health into target_health_ from mobjs where session_token=session_ and mobj_id=target_;
  select ammo_bullets,refire into ammo_,refire_ from players where session_token=session_
    and player_id=(select current_player_id from game_sessions where session_token=session_);
  select count(distinct q.request_id),count(case when event_type='DAMAGE' then 1 end),
    count(case when event_type='HITSCAN_HIT' then 1 end)
    into requests_,damage_,hits_ from doom_worker_request q
    left join game_events e on e.session_token=q.session_token and e.tic=q.expected_tic+1
    where q.session_token=session_ and q.request_status='COMMITTED';
  select max(a.detail) into parity_ from doom_worker_request q join doom_worker_audit a
    on a.request_id=q.request_id where q.session_token=session_ and a.audit_event='PARITY_OK';
  dbms_output.put_line('FIRE_DIAGNOSTIC tic='||tic_||' seq='||seq_||' requests='||requests_||
    ' health='||target_health_||' ammo='||ammo_||' refire='||refire_||' rng='||rng_||
    ' damage/hit='||damage_||'/'||hits_||' parity='||parity_);
  if tic_<>2 or seq_<>2 or requests_<>2 or target_health_ not between 91 and 97 or
     ammo_<>49 or refire_<>0 or rng_<3 or damage_<>1 or hits_<>1 or parity_ not like 'OK|%' then
    raise_application_error(-20000,'retained fire acceptance mismatch');
  end if;
  dbms_output.put_line('AUTOREST_WORKER_FIRE_OK tic='||tic_||' seq='||seq_||
    ' health='||target_health_||' ammo='||ammo_||' rng='||rng_||
    ' parity='||parity_||' bytes='||dbms_lob.getlength(payload_));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;diagnostic_ varchar2(4000);begin
    begin select max(a.audit_event||':'||a.detail) keep(dense_rank last order by a.audit_id)
      into diagnostic_ from doom_worker_request q join doom_worker_audit a on a.request_id=q.request_id
      where q.session_token=session_;exception when others then diagnostic_:=sqlerrm;end;
    dbms_output.put_line('FIRE_FAILURE_DIAGNOSTIC '||diagnostic_);cleanup_;
    raise_application_error(-20000,'fire acceptance failed ['||code_||'] '||message_);end;
end;
/
exit
