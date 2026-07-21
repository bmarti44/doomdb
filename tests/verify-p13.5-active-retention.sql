whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_mode varchar2(16);l_skill number;l_episode number;l_map number;l_max number;
  l_members number;l_ready_count number;l_requester number;l_epoch number;
  l_generation number;l_tic number;l_accepted number;l_ready number;l_payload blob;
  l_worker_mode varchar2(16);
  l_frames number;l_checkpoints number;l_tics number;l_commands number;
  l_job varchar2(64);
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
  doom_api.create_match('COOP',3,1,1,'RETENTION0',l_match,l_host,l_join,l_p0);
  l_p1:=null;doom_api.join_match(l_match,l_join,'RETENTION1',l_p1,l_slot);
  doom_api.ready_match(l_match,l_p0,1,l_state);
  doom_api.ready_match(l_match,l_p1,1,l_state);
  if l_state='STARTING' then
    for i in 1..1800 loop
      doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
        l_max,l_members,l_ready_count,l_requester,l_epoch,l_generation,l_tic,l_worker_mode);
      exit when l_state='ACTIVE';dbms_session.sleep(.1);
    end loop;
  end if;
  doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
    l_max,l_members,l_ready_count,l_requester,l_epoch,l_generation,l_tic,l_worker_mode);
  if l_state<>'ACTIVE' then raise_application_error(-20000,'retention start failed');end if;
  for i in 1..160 loop
    doom_match_worker.submit_command(l_match,0,l_epoch,l_generation,i,i,
      hextoraw('0800000000000000'),l_accepted);
    doom_match_worker.submit_command(l_match,1,l_epoch,l_generation,i,i,
      hextoraw('0000000000000000'),l_accepted);
    for p in 1..1000 loop
      doom_match_worker.poll_frame(l_match,0,l_epoch,l_generation,i,l_ready,l_payload);
      exit when l_ready=1;dbms_session.sleep(.005);
    end loop;
    if l_ready<>1 then raise_application_error(-20000,'retention frame timeout');end if;
  end loop;
  select count(*) into l_frames from doom_match_frame where match_id=l_match;
  select count(*) into l_checkpoints from doom_match_checkpoint where match_id=l_match;
  select count(*) into l_tics from doom_match_tic where match_id=l_match;
  select count(*) into l_commands from doom_match_command where match_id=l_match;
  if l_frames<>258 or l_checkpoints<>1 or l_tics<>161 or l_commands<>320 then
    raise_application_error(-20000,'retention bounds frames='||l_frames||
      ' checkpoints='||l_checkpoints||' tics='||l_tics||' commands='||l_commands);
  end if;
  cleanup_;
  dbms_output.put_line('PASS P13.5-ACTIVE-RETENTION frame-ring=128 checkpoint=1 ledger=complete');
exception when others then rollback;cleanup_;raise;
end;
/
