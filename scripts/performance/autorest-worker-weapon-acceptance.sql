whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  session_ varchar2(32);payload_ blob;commands_ clob;
  tic_ number;seq_ number;requests_ number;delta_v2_ number;delta_v1_ number;
  selected_ varchar2(32);pending_ varchar2(32);weapon_state_ varchar2(64);
  weapon_tics_ number;lower_events_ number;raise_events_ number;
  first_frame_ varchar2(64);final_frame_ varchar2(64);parity_ varchar2(4000);
  old_enabled_ number;old_parity_interval_ number;parity_count_ number;
  procedure step_(p_seq number,p_weapon number) is
  begin
    commands_:='{"v":1,"commands":[{"seq":'||p_seq||',"turn":0,"forward":0,'||
      '"strafe":0,"run":0,"fire":0,"use":0,"weapon":'||p_weapon||
      ',"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(session_,commands_,payload_);
    if payload_ is null or dbms_lob.getlength(payload_)=0 then
      raise_application_error(-20000,'empty weapon frame');
    end if;
  end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop(session_);exception when others then null;end;
    if old_enabled_ is not null then
      update doom_config set number_value=old_enabled_ where config_key='UNIFIED_WORKER_ENABLED';
    end if;
    if old_parity_interval_ is not null then
      update doom_config set number_value=old_parity_interval_
        where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
    end if;
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_interval_ from doom_config
    where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  commit;
  doom_api.new_game(3,session_,payload_);
  update players set weapon_mask=7,ammo_shells=8
    where session_token=session_ and player_id=(
      select current_player_id from game_sessions where session_token=session_);
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  commit;

  step_(1,3);
  select selected_weapon,pending_weapon,weapon_state,weapon_state_tics
    into selected_,pending_,weapon_state_,weapon_tics_ from players
    where session_token=session_ and player_id=(
      select current_player_id from game_sessions where session_token=session_);
  select frame_sha into first_frame_ from doom_worker_result r join doom_worker_request q
    on q.request_id=r.request_id where q.session_token=session_ and r.committed_command_seq=1;
  if selected_<>'PISTOL' or pending_<>'SHOTGUN' or
     weapon_state_<>'WEAPON_PISTOL_LOWER' or weapon_tics_<>2 then
    raise_application_error(-20000,'weapon lower transition mismatch');
  end if;

  step_(2,0);
  step_(3,0);
  for seq in 4..9 loop step_(seq,0);end loop;
  select current_tic,last_command_seq into tic_,seq_ from game_sessions
    where session_token=session_;
  select selected_weapon,pending_weapon,weapon_state,weapon_state_tics
    into selected_,pending_,weapon_state_,weapon_tics_ from players
    where session_token=session_ and player_id=(
      select current_player_id from game_sessions where session_token=session_);
  select count(*),count(case when r.delta_version=2 then 1 end),
    count(case when r.delta_version=1 then 1 end),max(case
      when r.committed_command_seq=9 then r.frame_sha end)
    into requests_,delta_v2_,delta_v1_,final_frame_
    from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
    where q.session_token=session_ and q.request_status='COMMITTED';
  select count(case when event_type='WEAPON_LOWER' then 1 end),
         count(case when event_type='WEAPON_RAISE' then 1 end)
    into lower_events_,raise_events_ from game_events where session_token=session_;
  select count(*),max(a.detail) into parity_count_,parity_
    from doom_worker_request q join doom_worker_audit a on a.request_id=q.request_id
    where q.session_token=session_ and a.audit_event='PARITY_OK';
  dbms_output.put_line('WEAPON_DIAGNOSTIC tic='||tic_||' seq='||seq_||
    ' requests='||requests_||' delta_v2/v1='||delta_v2_||'/'||delta_v1_||' selected='||selected_||
    ' pending='||coalesce(pending_,'NULL')||' state='||weapon_state_||'/'||weapon_tics_||
    ' events='||lower_events_||'/'||raise_events_||' parity_count='||parity_count_||' frames_equal='||
    case when first_frame_=final_frame_ then 1 else 0 end||' parity='||parity_);
  if tic_<>9 or seq_<>9 or requests_<>9 or delta_v2_<>8 or delta_v1_<>1 or
     selected_<>'SHOTGUN' or pending_ is not null or
     weapon_state_<>'WEAPON_SHOTGUN_READY' or weapon_tics_<>1 or
     lower_events_<>1 or raise_events_<>1 or first_frame_=final_frame_ or
     parity_count_<>9 or parity_ not like 'OK|%' then
    raise_application_error(-20000,'retained weapon acceptance mismatch');
  end if;
  dbms_output.put_line('AUTOREST_WORKER_WEAPON_OK tic='||tic_||' seq='||seq_||
    ' deltas_v2/v1='||delta_v2_||'/'||delta_v1_||' events='||lower_events_||'/'||raise_events_||
    ' parity='||parity_||' bytes='||dbms_lob.getlength(payload_));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;begin
    cleanup_;
    raise_application_error(-20000,'weapon acceptance failed ['||code_||'] '||message_);
  end;
end;
/

exit
