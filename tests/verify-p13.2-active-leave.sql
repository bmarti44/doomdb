whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_mode varchar2(16);l_skill number;l_episode number;l_map number;l_max number;
  l_members number;l_ready_count number;l_requester number;l_epoch number;
  l_generation number;l_tic number;l_accepted number;l_ready number;l_payload blob;
  l_job varchar2(64);l_count number;l_bitmap varchar2(2);l_source varchar2(16);
  procedure status_ is
  begin
    doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
      l_max,l_members,l_ready_count,l_requester,l_epoch,l_generation,l_tic);
  end;
  procedure cleanup_ is
  begin
    if l_match is null then return;end if;
    begin
      select job_name,generation into l_job,l_generation
        from doom_match_worker_control where match_id=l_match;
      doom_match_worker.stop_match(l_match,l_generation);dbms_session.sleep(.2);
      begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    exception when no_data_found then null;end;
    delete from doom_match where match_id=l_match;commit;
  end;
begin
  doom_api.create_match('COOP',3,1,1,'LEAVE0',l_match,l_host,l_join,l_p0);
  l_p1:=null;doom_api.join_match(l_match,l_join,'LEAVE1',l_p1,l_slot);
  doom_api.ready_match(l_match,l_p0,1,l_state);
  doom_api.ready_match(l_match,l_p1,1,l_state);
  if l_state='STARTING' then
    for i in 1..1800 loop status_;exit when l_state='ACTIVE';dbms_session.sleep(.1);end loop;
  end if;
  status_;
  if l_state<>'ACTIVE' or l_tic<>0 then raise_application_error(-20000,'leave start');end if;

  doom_api.leave_match(l_match,l_p1,l_state);
  if l_state<>'ACTIVE' then raise_application_error(-20000,'guest leave state');end if;
  select leave_tic into l_tic from doom_match_member where match_id=l_match and player_slot=1;
  if l_tic<>1 then raise_application_error(-20000,'guest leave boundary');end if;
  doom_api.submit_match_step(l_match,l_p0,1,1,'0800000000000000',
    l_accepted,l_epoch,l_generation);
  for i in 1..1000 loop
    doom_api.poll_match_frame(l_match,l_p0,1,100,l_ready,l_tic,l_payload);
    exit when l_ready=1;dbms_session.sleep(.01);
  end loop;
  if l_ready<>1 or l_tic<>1 then raise_application_error(-20000,'left tic timeout');end if;
  select rawtohex(membership_bitmap),rawtohex(neutral_bitmap) into l_bitmap,l_join
    from doom_match_tic where match_id=l_match and tic=1;
  select command_source into l_source from doom_match_command
    where match_id=l_match and tic=1 and player_slot=1;
  select count(*) into l_count from doom_match_frame where match_id=l_match and tic=1;
  if l_bitmap<>'01' or l_join<>'02' or l_source<>'NEUTRAL_LEFT' or l_count<>1 then
    raise_application_error(-20000,'left frontier mismatch');
  end if;

  select job_name into l_job from doom_match_worker_control where match_id=l_match;
  begin dbms_scheduler.stop_job(l_job,true);exception when others then null;end;
  begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
  doom_match_worker.recover_match(l_match,180000,l_state);status_;
  if l_state<>'ACTIVE' or l_generation<>2 or l_tic<>1 then
    raise_application_error(-20000,'left reconstruction mismatch');
  end if;
  doom_api.leave_match(l_match,l_p0,l_state);
  if l_state<>'FINISHED' then raise_application_error(-20000,'host finish');end if;
  doom_api.leave_match(l_match,l_p0,l_state);
  if l_state<>'FINISHED' then raise_application_error(-20000,'host finish retry');end if;
  cleanup_;
  dbms_output.put_line('PASS P13.2-ACTIVE-LEAVE boundary=1 membership=01 neutral-left one-POV reconstruct finish');
exception when others then rollback;cleanup_;raise;
end;
/
