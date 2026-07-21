whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  m varchar2(32);h varchar2(64);j varchar2(64);p0 varchar2(64);p1 varchar2(64);
  s varchar2(32);mode_ varchar2(16);slot number;skill_ number;episode_ number;
  map_ number;max_ number;members_ number;ready_ number;requester_ number;
  epoch_ number;generation_ number;tic_ number;accepted_ number;ready_frame number;
  worker_mode_ varchar2(16);
  payload_ blob;job_ varchar2(64);state_sha_ varchar2(64);frame0_ varchar2(64);
  frame1_ varchar2(64);state_after_ varchar2(64);frame0_after_ varchar2(64);
  frame1_after_ varchar2(64);

  procedure status_ is
  begin
    doom_api.match_status(m,h,s,mode_,skill_,episode_,map_,max_,members_,
      ready_,requester_,epoch_,generation_,tic_,worker_mode_);
  end;

  procedure cleanup_ is
  begin
    if m is null then return;end if;
    begin
      select job_name,generation into job_,generation_
        from doom_match_worker_control where match_id=m;
      doom_match_worker.stop_match(m,generation_);dbms_session.sleep(.2);
      begin dbms_scheduler.drop_job(job_,true);exception when others then null;end;
    exception when no_data_found then null;end;
    delete from doom_match where match_id=m;commit;
  end;
begin
  doom_api.create_match('DEATHMATCH',3,1,1,'DM HOST',m,h,j,p0);
  p1:=null;doom_api.join_match(m,j,'DM GUEST',p1,slot);
  doom_api.ready_match(m,p0,1,s);doom_api.ready_match(m,p1,1,s);
  if s='STARTING' then
    for i in 1..1800 loop status_;exit when s='ACTIVE';dbms_session.sleep(.1);end loop;
  end if;
  status_;
  if s<>'ACTIVE' or mode_<>'DEATHMATCH' or generation_<>1 or tic_<>0 then
    raise_application_error(-20000,'deathmatch start mismatch');
  end if;
  doom_match_worker.submit_command(m,0,epoch_,generation_,1,1,
    hextoraw('0000000000000000'),accepted_);
  doom_match_worker.submit_command(m,1,epoch_,generation_,1,1,
    hextoraw('0000000000000000'),accepted_);
  for i in 1..30000 loop
    doom_match_worker.poll_frame(m,0,epoch_,generation_,1,ready_frame,payload_);
    exit when ready_frame=1;dbms_session.sleep(.002);
  end loop;
  if ready_frame<>1 then raise_application_error(-20000,'deathmatch tic timeout');end if;
  select t.state_sha,max(case f.player_slot when 0 then f.frame_sha end),
    max(case f.player_slot when 1 then f.frame_sha end)
    into state_sha_,frame0_,frame1_
    from doom_match_tic t join doom_match_frame f
      on f.match_id=t.match_id and f.tic=t.tic
    where t.match_id=m and t.tic=1 group by t.state_sha;
  if frame0_=frame1_ then raise_application_error(-20000,'deathmatch POVs collapsed');end if;

  select job_name into job_ from doom_match_worker_control where match_id=m;
  begin dbms_scheduler.stop_job(job_,true);exception when others then null;end;
  begin dbms_scheduler.drop_job(job_,true);exception when others then null;end;
  doom_match_worker.recover_match(m,180000,s);status_;
  if s<>'ACTIVE' or generation_<>2 or tic_<>1 then
    raise_application_error(-20000,'deathmatch recovery mismatch');
  end if;
  select t.state_sha,max(case f.player_slot when 0 then f.frame_sha end),
    max(case f.player_slot when 1 then f.frame_sha end)
    into state_after_,frame0_after_,frame1_after_
    from doom_match_tic t join doom_match_frame f
      on f.match_id=t.match_id and f.tic=t.tic
    where t.match_id=m and t.tic=1 group by t.state_sha;
  if state_after_<>state_sha_ or frame0_after_<>frame0_ or frame1_after_<>frame1_ then
    raise_application_error(-20000,'deathmatch recovery hashes changed');
  end if;
  cleanup_;
  dbms_output.put_line('PASS P13.4-DEATHMATCH-LIFECYCLE two-POV tic=1 exact-recovery');
exception when others then rollback;cleanup_;raise;
end;
/
