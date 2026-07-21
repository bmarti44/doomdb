whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  match_ varchar2(32);host_ varchar2(64);join_ varchar2(64);
  player0_ varchar2(64);player1_ varchar2(64);player1_retry_ varchar2(64);
  player1_old_ varchar2(64);slot_ number;state_ varchar2(32);mode_ varchar2(16);
  skill_ number;episode_ number;map_ number;max_ number;members_ number;
  ready_ number;requester_ number;epoch_ number;generation_ number;tic_ number;
  worker_mode_ varchar2(16);
  code1_ number;code2_ number;message1_ varchar2(4000);message2_ varchar2(4000);
  count_ number;third_ varchar2(64);
  expiry_before_ timestamp with time zone;

  procedure status_(match_id_ varchar2,capability_ varchar2) is
  begin
    doom_api.match_status(match_id_,capability_,state_,mode_,skill_,episode_,
      map_,max_,members_,ready_,requester_,epoch_,generation_,tic_,worker_mode_);
  end;

  procedure capture_status_(
    match_id_ varchar2,capability_ varchar2,code_ out number,message_ out varchar2
  ) is
  begin
    code_:=0;message_:=null;status_(match_id_,capability_);
  exception when others then code_:=sqlcode;message_:=sqlerrm;
  end;
begin
  doom_api.create_match('COOP',3,1,1,'HOST',match_,host_,join_,player0_);
  if not regexp_like(match_,'^[0-9a-f]{32}$') or
     not regexp_like(host_,'^[0-9a-f]{64}$') or
     not regexp_like(join_,'^[0-9a-f]{64}$') or
     not regexp_like(player0_,'^[0-9a-f]{64}$') then
    raise_application_error(-20000,'create capability shape');
  end if;
  select count(*) into count_ from doom_match
    where match_id=match_ and
      host_capability_hash not in(host_,join_,player0_) and
      join_capability_hash not in(host_,join_,player0_) and
      rawtohex(host_capability_salt)<>upper(substr(host_,1,64)) and
      rawtohex(join_capability_salt)<>upper(substr(join_,1,64));
  if count_<>1 then raise_application_error(-20000,'bearer persisted');end if;

  status_(match_,host_);
  if state_<>'LOBBY' or mode_<>'COOP' or skill_<>3 or episode_<>1 or map_<>1 or
     max_<>2 or members_<>1 or ready_<>0 or requester_<>-1 or
     epoch_<>1 or generation_<>0 or tic_<>0 then
    raise_application_error(-20000,'host status mismatch');
  end if;
  update doom_match set expires_at=systimestamp+interval '15' minute
    where match_id=match_;
  commit;
  select expires_at into expiry_before_ from doom_match where match_id=match_;
  status_(match_,host_);
  select count(*) into count_ from doom_match where match_id=match_
    and expires_at=expiry_before_;
  if count_<>1 then raise_application_error(-20000,'healthy lease renewed too eagerly');end if;
  update doom_match set expires_at=systimestamp+interval '5' second
    where match_id=match_;
  commit;
  status_(match_,host_);
  select count(*) into count_ from doom_match where match_id=match_
    and expires_at>systimestamp+interval '19' minute;
  if count_<>1 then raise_application_error(-20000,'authenticated idle lease did not renew');end if;
  capture_status_(rpad('0',32,'0'),rpad('f',64,'f'),code1_,message1_);
  capture_status_(match_,rpad('f',64,'f'),code2_,message2_);
  if code1_<>-20713 or code2_<>-20713 or message1_<>message2_ then
    raise_application_error(-20000,'auth/enumeration shape differs');
  end if;

  player1_:=null;
  doom_api.join_match(match_,join_,'JOINER',player1_,slot_);
  if slot_<>1 or not regexp_like(player1_,'^[0-9a-f]{64}$') then
    raise_application_error(-20000,'join failed');
  end if;
  player1_retry_:=player1_;
  doom_api.join_match(match_,join_,'JOINER',player1_retry_,slot_);
  if slot_<>1 or player1_retry_<>player1_ then
    raise_application_error(-20000,'join retry changed identity');
  end if;
  third_:=null;
  begin
    doom_api.join_match(match_,join_,'THIRD',third_,slot_);
    raise_application_error(-20000,'full-match join succeeded');
  exception when others then
    if sqlcode=-20000 then raise;end if;
    if sqlcode<>-20702 then raise_application_error(-20000,'capacity code');end if;
  end;

  doom_api.ready_match(match_,player0_,1,state_);
  if state_<>'LOBBY' then raise_application_error(-20000,'premature start');end if;
  status_(match_,player1_);
  if requester_<>1 or state_<>'LOBBY' or members_<>2 or ready_<>1 or
     generation_<>0 or tic_<>0 then
    raise_application_error(-20000,'ready status mismatch');
  end if;
  select count(*) into count_ from doom_match_tic where match_id=match_;
  if count_<>0 then raise_application_error(-20000,'fabricated tic zero');end if;

  player1_old_:=player1_;
  doom_api.leave_match(match_,player1_,state_);
  if state_<>'LOBBY' then raise_application_error(-20000,'guest leave');end if;
  doom_api.leave_match(match_,player1_,state_);
  if state_<>'LOBBY' then raise_application_error(-20000,'leave retry');end if;
  player1_:=null;
  doom_api.join_match(match_,join_,'REJOINED',player1_,slot_);
  if slot_<>1 or player1_=player1_old_ then
    raise_application_error(-20000,'slot reconnect rotation');
  end if;
  capture_status_(match_,player1_old_,code1_,message1_);
  if code1_<>-20713 then raise_application_error(-20000,'old capability replay');end if;

  doom_api.leave_match(match_,player0_,state_);
  if state_<>'CANCELLED' then raise_application_error(-20000,'host cancel');end if;
  doom_api.leave_match(match_,player0_,state_);
  if state_<>'CANCELLED' then raise_application_error(-20000,'host cancel retry');end if;

  update doom_match set created_at=created_at-interval '1' hour,
    expires_at=systimestamp-interval '1' second
    where match_id=match_;
  commit;
  capture_status_(match_,host_,code1_,message1_);
  if code1_<>-20713 then raise_application_error(-20000,'expiry fence');end if;

  delete from doom_match where match_id=match_;commit;
  dbms_output.put_line('PASS P13.1-MULTIPLAYER-API-LIVE auth/race/retry/'||
    'expiry/reconnect/leave/start-boundary');
exception when others then
  rollback;
  if match_ is not null then delete from doom_match where match_id=match_;commit;end if;
  raise;
end;
/
