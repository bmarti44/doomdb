whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  retained_session_ varchar2(32);oracle_session_ varchar2(32);payload_ blob;commands_ clob;
  retained_events_ clob;oracle_events_ clob;retained_world_ clob;oracle_world_ clob;
  retained_player_ clob;oracle_player_ clob;
  old_enabled_ number;old_parity_ number;
  procedure fixture_(p_session varchar2) is
    x_ number;y_ number;angle_ number;sector_ number;barrel1_ number;barrel2_ number;monster_ number;
  begin
    select p.x,p.y,p.angle into x_,y_,angle_ from players p join game_sessions s
      on s.session_token=p.session_token and s.current_player_id=p.player_id
      where p.session_token=p_session;
    select sector_id into sector_ from table(doom_bsp_locate(x_,y_)) where rownum=1;
    update players set health=100,armor=50,armor_type=1,alive=1
      where session_token=p_session;
    update mobjs set health=0,exploded=1 where session_token=p_session and thing_type=2035;
    update mobjs m set health=0,monster_health_seen=0,death_processed=1,awake=0,state_tics=0
      where m.session_token=p_session and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    update mobjs m set sector_id=(select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1)
      where m.session_token=p_session and m.sector_id is null and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    select min(mobj_id) into barrel1_ from mobjs
      where session_token=p_session and thing_type=2035;
    select min(mobj_id) into barrel2_ from mobjs
      where session_token=p_session and thing_type=2035 and mobj_id>barrel1_;
    select min(m.mobj_id) into monster_ from mobjs m join doom_monster_def d
      on d.thing_type=m.thing_type where m.session_token=p_session;
    update mobjs set x=x_+cos(angle_*acos(-1)/180)*16,
      y=y_+sin(angle_*acos(-1)/180)*16,sector_id=sector_,health=1,exploded=0
      where session_token=p_session and mobj_id=barrel1_;
    update mobjs set x=x_+cos(angle_*acos(-1)/180)*48,
      y=y_+sin(angle_*acos(-1)/180)*48,sector_id=sector_,health=20,exploded=0
      where session_token=p_session and mobj_id=barrel2_;
    update mobjs set x=x_+cos(angle_*acos(-1)/180)*80,
      y=y_+sin(angle_*acos(-1)/180)*80,sector_id=sector_,health=100,
      monster_health_seen=100,death_processed=0,awake=0
      where session_token=p_session and mobj_id=monster_;
  end;
  procedure snapshot_(p_session varchar2,p_events out clob,p_world out clob,p_player out clob) is
  begin
    select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
        number_value,text_value null on null returning varchar2)
        order by event_ordinal returning clob)
      into p_events from game_events where session_token=p_session and tic=1;
    select json_arrayagg(json_array(mobj_id,thing_type,x,y,health,exploded,
        monster_health_seen,death_processed,target_mobj_id,tracer_mobj_id,owner_mobj_id
        null on null returning varchar2) order by mobj_id returning clob)
      into p_world from mobjs where session_token=p_session and
        (thing_type=2035 or exists(select 1 from doom_monster_def d where d.thing_type=mobjs.thing_type));
    select json_object('health' value health,'armor' value armor,'alive' value alive,
        'ammo' value ammo_bullets,'refire' value refire returning clob)
      into p_player from players where session_token=p_session and
        player_id=(select current_player_id from game_sessions where session_token=p_session);
  end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop(retained_session_);exception when others then null;end;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if retained_session_ is not null then delete from game_sessions where session_token=retained_session_;end if;
    if oracle_session_ is not null then delete from game_sessions where session_token=oracle_session_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';commit;
  doom_api.new_game(3,retained_session_,payload_);fixture_(retained_session_);commit;
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';commit;
  commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,"strafe":0,'||
    '"run":0,"fire":1,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
  doom_api.step(retained_session_,commands_,payload_);
  snapshot_(retained_session_,retained_events_,retained_world_,retained_player_);

  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';commit;
  doom_api.new_game(3,oracle_session_,payload_);fixture_(oracle_session_);commit;
  doom_api.step(oracle_session_,commands_,payload_);
  snapshot_(oracle_session_,oracle_events_,oracle_world_,oracle_player_);
  if dbms_lob.compare(retained_events_,oracle_events_)<>0 or
     dbms_lob.compare(retained_world_,oracle_world_)<>0 or
     dbms_lob.compare(retained_player_,oracle_player_)<>0 then
    dbms_output.put_line('BARREL_RETAINED_EVENTS '||dbms_lob.substr(retained_events_,4000,1));
    dbms_output.put_line('BARREL_ORACLE_EVENTS '||dbms_lob.substr(oracle_events_,4000,1));
    dbms_output.put_line('BARREL_RETAINED_PLAYER '||dbms_lob.substr(retained_player_,4000,1));
    dbms_output.put_line('BARREL_ORACLE_PLAYER '||dbms_lob.substr(oracle_player_,4000,1));
    raise_application_error(-20000,'retained/SQL barrel differential mismatch');
  end if;
  dbms_output.put_line('AUTOREST_WORKER_BARREL_OK event_bytes='||dbms_lob.getlength(retained_events_)||
    ' player='||dbms_lob.substr(retained_player_,4000,1)||
    ' bytes='||dbms_lob.getlength(payload_));
  dbms_output.put_line('AUTOREST_WORKER_BARREL_EVENTS '||dbms_lob.substr(retained_events_,4000,1));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;diagnostic_ varchar2(4000);begin
    begin select max(a.audit_event||':'||a.detail) keep(dense_rank last order by a.audit_id)
      into diagnostic_ from doom_worker_request q join doom_worker_audit a on a.request_id=q.request_id
      where q.session_token=retained_session_;exception when others then diagnostic_:=sqlerrm;end;
    dbms_output.put_line('BARREL_FAILURE_DIAGNOSTIC '||diagnostic_);cleanup_;
    raise_application_error(-20000,'barrel acceptance failed ['||code_||'] '||message_);end;
end;
/
exit
