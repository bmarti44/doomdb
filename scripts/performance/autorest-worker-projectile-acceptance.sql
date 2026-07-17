whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  retained_ varchar2(32);oracle_ varchar2(32);payload_ blob;commands_ clob;
  request_ varchar2(32);ready_ number;
  retained_projectile_ clob;oracle_projectile_ clob;retained_events_ clob;oracle_events_ clob;
  retained_player_ clob;oracle_player_ clob;old_enabled_ number;old_parity_ number;
  procedure fixture_(p_session varchar2) is
    x_ number;y_ number;angle_ number;sector_ number;target_ number;
  begin
    select p.x,p.y,p.angle into x_,y_,angle_ from players p join game_sessions s
      on s.session_token=p.session_token and s.current_player_id=p.player_id
      where p.session_token=p_session;
    select sector_id into sector_ from table(doom_bsp_locate(x_,y_)) where rownum=1;
    update players set weapon_mask=31,selected_weapon='ROCKET_LAUNCHER',pending_weapon=null,
      weapon_state='WEAPON_ROCKET_LAUNCHER_READY',weapon_state_tics=0,
      flash_state=null,flash_state_tics=0,refire=0,ammo_rockets=10
      where session_token=p_session;
    update mobjs set health=0,exploded=1 where session_token=p_session and thing_type=2035;
    update mobjs m set health=0,monster_health_seen=0,death_processed=1,awake=0,state_tics=0
      where m.session_token=p_session and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    update mobjs m set sector_id=(select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1)
      where m.session_token=p_session and m.sector_id is null and exists(
        select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    select min(m.mobj_id) into target_ from mobjs m join doom_monster_def d
      on d.thing_type=m.thing_type where m.session_token=p_session and d.drop_thing_type is not null;
    update mobjs set x=x_+cos(angle_*acos(-1)/180)*16,
      y=y_+sin(angle_*acos(-1)/180)*16,sector_id=sector_,health=10,
      monster_health_seen=10,death_processed=0,awake=0
      where session_token=p_session and mobj_id=target_;
  end;
  procedure snapshot_(p_session varchar2,p_projectile out clob,p_events out clob,p_player out clob) is
  begin
    select json_arrayagg(json_array(mobj_id,thing_type,state_id,state_tics,x,y,z,
        momentum_x,momentum_y,momentum_z,angle,radius,height,health,owner_mobj_id,
        projectile_kind,sector_id null on null returning varchar2)
        order by mobj_id returning clob)
      into p_projectile from mobjs where session_token=p_session and projectile_kind is not null;
    select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
        number_value,text_value null on null returning varchar2)
        order by event_ordinal returning clob)
      into p_events from game_events where session_token=p_session and tic=1;
    select json_object('health' value health,'armor' value armor,'alive' value alive,
        'rockets' value ammo_rockets,'weapon' value selected_weapon,
        'state' value weapon_state,'tics' value weapon_state_tics,'refire' value refire returning clob)
      into p_player from players where session_token=p_session and
        player_id=(select current_player_id from game_sessions where session_token=p_session);
  end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop(retained_);exception when others then null;end;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if retained_ is not null then delete from game_sessions where session_token=retained_;end if;
    if oracle_ is not null then delete from game_sessions where session_token=oracle_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';commit;
  doom_api.new_game(3,retained_,payload_);fixture_(retained_);commit;
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';commit;
  commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,"strafe":0,'||
    '"run":0,"fire":1,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
  -- Exercise the same two-call AutoREST contract used by the browser.  FIRE
  -- must remain a predecessor-independent ticcmd at submit time while the
  -- resident worker serializes and commits its DMSC/v4 result.
  doom_api.submit_step(retained_,commands_,request_);
  doom_api.poll_frame(retained_,1,1000,ready_,payload_);
  if request_ is null or ready_<>1 or payload_ is null then
    raise_application_error(-20000,'projectile async response was not ready');
  end if;
  snapshot_(retained_,retained_projectile_,retained_events_,retained_player_);
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';commit;
  doom_api.new_game(3,oracle_,payload_);fixture_(oracle_);commit;
  doom_api.step(oracle_,commands_,payload_);
  snapshot_(oracle_,oracle_projectile_,oracle_events_,oracle_player_);
  if dbms_lob.compare(retained_projectile_,oracle_projectile_)<>0 or
     dbms_lob.compare(retained_events_,oracle_events_)<>0 or
     dbms_lob.compare(retained_player_,oracle_player_)<>0 then
    dbms_output.put_line('PROJECTILE_RETAINED '||dbms_lob.substr(retained_projectile_,4000,1));
    dbms_output.put_line('PROJECTILE_ORACLE '||dbms_lob.substr(oracle_projectile_,4000,1));
    dbms_output.put_line('PROJECTILE_RETAINED_EVENTS '||dbms_lob.substr(retained_events_,4000,1));
    dbms_output.put_line('PROJECTILE_ORACLE_EVENTS '||dbms_lob.substr(oracle_events_,4000,1));
    raise_application_error(-20000,'retained/SQL projectile differential mismatch');
  end if;
  declare versions_ varchar2(100);begin
    select max(command_version)||'/'||max(delta_version) into versions_
      from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
      where q.session_token=retained_;
    if versions_<>'4/3' then raise_application_error(-20000,'projectile protocol '||versions_);end if;
    dbms_output.put_line('AUTOREST_WORKER_PROJECTILE_OK versions='||versions_||
      ' projectile='||coalesce(dbms_lob.substr(retained_projectile_,4000,1),'TRANSIENT')||
      ' events='||dbms_lob.substr(retained_events_,4000,1));
  end;
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;diagnostic_ varchar2(4000);begin
    begin select max(a.audit_event||':'||a.detail) keep(dense_rank last order by a.audit_id)
      into diagnostic_ from doom_worker_request q join doom_worker_audit a on a.request_id=q.request_id
      where q.session_token=retained_;exception when others then diagnostic_:=sqlerrm;end;
    dbms_output.put_line('PROJECTILE_FAILURE_DIAGNOSTIC '||diagnostic_);
    for r in (select a.audit_event,a.detail from doom_worker_request q join doom_worker_audit a
        on a.request_id=q.request_id where q.session_token=retained_ order by a.audit_id) loop
      dbms_output.put_line('PROJECTILE_AUDIT '||r.audit_event||':'||r.detail);
    end loop;
    cleanup_;
    raise_application_error(-20000,'projectile acceptance failed ['||code_||'] '||message_);end;
end;
/
exit
