whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  match1_ varchar2(32);host1_ varchar2(64);join1_ varchar2(64);
  p10_ varchar2(64);p11_ varchar2(64);match2_ varchar2(32);
  host2_ varchar2(64);join2_ varchar2(64);p20_ varchar2(64);p21_ varchar2(64);
  slot_ number;state_ varchar2(32);mode_ varchar2(16);skill_ number;
  episode_ number;map_ number;max_ number;members_ number;ready_count_ number;
  requester_ number;epoch1_ number;generation1_ number;tic_ number;
  epoch2_ number;generation2_ number;accepted_ number;ready_ number;
  payload0_ blob;payload1_ blob;count_ number;vector_ varchar2(64);
  frame0_ varchar2(64);frame1_ varchar2(64);root1_ varchar2(64);
  root2_ varchar2(64);job_ varchar2(64);

  procedure status_(match_id_ varchar2,capability_ varchar2) is
  begin
    doom_api.match_status(match_id_,capability_,state_,mode_,skill_,episode_,
      map_,max_,members_,ready_count_,requester_,epoch1_,generation1_,tic_);
  end;

  procedure cleanup_(match_id_ varchar2) is
    generation_local_ number;
  begin
    if match_id_ is null then return;end if;
    begin
      select job_name,generation into job_,generation_local_
        from doom_match_worker_control where match_id=match_id_;
      doom_match_worker.stop_match(match_id_,generation_local_);
      dbms_session.sleep(.2);
      begin dbms_scheduler.drop_job(job_,true);exception when others then null;end;
    exception when no_data_found then null;end;
    delete from doom_match where match_id=match_id_;commit;
  end;

  procedure start_(
    name_ varchar2,match_ out varchar2,host_ out varchar2,join_ out varchar2,
    p0_ out varchar2,p1_ out varchar2,epoch_ out number,generation_ out number
  ) is
  begin
    doom_api.create_match('COOP',3,1,1,name_||'0',match_,host_,join_,p0_);
    p1_:=null;doom_api.join_match(match_,join_,name_||'1',p1_,slot_);
    if slot_<>1 then raise_application_error(-20000,'join slot');end if;
    doom_api.ready_match(match_,p0_,1,state_);
    if state_<>'LOBBY' then raise_application_error(-20000,'premature start');end if;
    doom_api.ready_match(match_,p1_,1,state_);
    if state_<>'ACTIVE' then raise_application_error(-20000,'real start failed '||state_);end if;
    status_(match_,host_);epoch_:=epoch1_;generation_:=generation1_;
    if state_<>'ACTIVE' or generation_<>1 or tic_<>0 then
      raise_application_error(-20000,'active frontier');
    end if;
    select count(*) into count_ from doom_match_tic where match_id=match_ and tic=0;
    if count_<>1 then raise_application_error(-20000,'tic zero absent');end if;
    select count(*) into count_ from doom_match_frame where match_id=match_ and tic=0
      and response_bytes=dbms_lob.getlength(response_blob);
    if count_<>2 then raise_application_error(-20000,'tic-zero frames absent');end if;
  end;
begin
  start_('WORKER_A',match1_,host1_,join1_,p10_,p11_,epoch1_,generation1_);

  -- Slot 1 arrives first; no world advance occurs until slot 0 completes the
  -- same fenced tic vector.
  doom_match_worker.submit_command(match1_,1,epoch1_,generation1_,1,1,
    hextoraw('00F8000000000000'),accepted_);
  if accepted_<>1 then raise_application_error(-20000,'slot1 rejected');end if;
  begin
    doom_match_worker.submit_command(match1_,0,epoch1_,generation1_,1,2,
      hextoraw('0800000000000000'),accepted_);
    raise_application_error(-20000,'non-monotonic command sequence accepted');
  exception when others then
    if sqlcode<>-20731 then raise;end if;
  end;
  select current_tic into tic_ from doom_match where match_id=match1_;
  if tic_<>0 then raise_application_error(-20000,'partial vector advanced');end if;
  doom_match_worker.submit_command(match1_,0,epoch1_,generation1_,1,1,
    hextoraw('0800000000000000'),accepted_);
  if accepted_<>1 then raise_application_error(-20000,'slot0 rejected');end if;
  for poll_ in 1..1000 loop
    doom_match_worker.poll_frame(match1_,0,epoch1_,generation1_,1,ready_,payload0_);
    exit when ready_=1;dbms_session.sleep(.01);
  end loop;
  if ready_<>1 then raise_application_error(-20000,'tic1 frame timeout');end if;
  doom_match_worker.poll_frame(match1_,1,epoch1_,generation1_,1,ready_,payload1_);
  if ready_<>1 then raise_application_error(-20000,'pov1 frame absent');end if;
  select current_tic into tic_ from doom_match where match_id=match1_;
  if tic_<>1 then raise_application_error(-20000,'world did not advance once');end if;
  select lower(rawtohex(command_vector)) into vector_ from doom_match_tic
    where match_id=match1_ and tic=1;
  if substr(vector_,1,16)<>'0800000000000000' or
     substr(vector_,17,16)<>'00f8000000000000' or
     substr(vector_,33)<>rpad('0',32,'0') then
    raise_application_error(-20000,'ordered vector mismatch '||vector_);
  end if;
  select min(frame_sha),max(frame_sha) into frame0_,frame1_ from doom_match_frame
    where match_id=match1_ and tic=1;
  if frame0_=frame1_ then raise_application_error(-20000,'POV frames collapsed');end if;

  -- Retry after commit returns the immutable command identity and cannot
  -- enqueue or advance a second tic.
  doom_match_worker.submit_command(match1_,0,epoch1_,generation1_,1,1,
    hextoraw('0800000000000000'),accepted_);
  dbms_session.sleep(.05);
  select current_tic into tic_ from doom_match where match_id=match1_;
  if tic_<>1 then raise_application_error(-20000,'duplicate advanced world');end if;

  start_('WORKER_B',match2_,host2_,join2_,p20_,p21_,epoch2_,generation2_);
  select previous_state_sha into root1_ from doom_match_tic
    where match_id=match1_ and tic=0;
  select previous_state_sha into root2_ from doom_match_tic
    where match_id=match2_ and tic=0;
  if root1_<>root2_ then
    raise_application_error(-20000,'canonical root depends on match identity');
  end if;
  select current_tic into tic_ from doom_match where match_id=match2_;
  if tic_<>0 then raise_application_error(-20000,'cross-match frontier leak');end if;
  select count(*) into count_ from doom_match_command where match_id=match2_;
  if count_<>0 then raise_application_error(-20000,'cross-match command leak');end if;

  cleanup_(match2_);cleanup_(match1_);
  dbms_output.put_line('PASS P13.2-RETAINED-MATCH-WORKER real-start/'||
    'arbitrary-arrival/one-tic/two-POV/idempotency/root/isolation');
exception when others then
  rollback;cleanup_(match2_);cleanup_(match1_);raise;
end;
/
