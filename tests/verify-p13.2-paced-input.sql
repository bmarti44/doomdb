whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_mode varchar2(16);l_worker_mode varchar2(16);l_skill number;l_episode number;
  l_map number;l_max number;l_members number;l_ready_count number;l_requester number;
  l_epoch number;l_generation number;l_tic number;l_accepted number;
  l_effective0 number;l_effective1 number;l_duplicate_tic number;l_error number:=0;
  l_source varchar2(24);l_raw varchar2(16);l_vector varchar2(64);
  l_job varchar2(64);l_frontier number;l_frontier_state varchar2(64);
  l_recovery varchar2(32);l_count number;
  l_target number;l_target_effective number;

  procedure status_ is
  begin
    doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
      l_max,l_members,l_ready_count,l_requester,l_epoch,l_generation,l_tic,
      l_worker_mode);
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
  select text_value into l_worker_mode from doom_config
    where config_key='MATCH_WORKER_MODE';
  if l_worker_mode<>'PACED_INPUT' then
    raise_application_error(-20000,'paced mode is not enabled');end if;

  doom_api.create_match('COOP',3,1,1,'PACED HOST',l_match,l_host,l_join,l_p0);
  l_p1:=null;doom_api.join_match(l_match,l_join,'PACED GUEST',l_p1,l_slot);
  doom_api.ready_match(l_match,l_p0,1,l_state);
  doom_api.ready_match(l_match,l_p1,1,l_state);
  for i in 1..1800 loop
    status_;exit when l_state='ACTIVE';dbms_session.sleep(.1);
  end loop;
  if l_state<>'ACTIVE' or l_worker_mode<>'PACED_INPUT' then
    raise_application_error(-20000,'paced match did not start');end if;

  doom_api.revise_match_input(l_match,l_p0,1,'0800000000000000',
    l_accepted,l_effective0,l_epoch,l_generation);
  if l_accepted<>1 then raise_application_error(-20000,'host input rejected');end if;
  doom_api.revise_match_input(l_match,l_p1,1,'00f8000000000000',
    l_accepted,l_effective1,l_epoch,l_generation);
  if l_accepted<>1 then raise_application_error(-20000,'guest input rejected');end if;
  doom_api.revise_match_input(l_match,l_p0,1,'0800000000000000',
    l_accepted,l_duplicate_tic,l_epoch,l_generation);
  if l_accepted<>1 or l_duplicate_tic<>l_effective0 then
    raise_application_error(-20000,'exact input retry changed');end if;
  begin
    doom_api.revise_match_input(l_match,l_p0,1,'0000000000000000',
      l_accepted,l_duplicate_tic,l_epoch,l_generation);
  exception when others then l_error:=sqlcode;end;
  if l_error=0 then raise_application_error(-20000,'mismatched retry accepted');end if;

  status_;l_target:=l_tic+5;
  doom_api.revise_match_input(l_match,l_p0,2,'0800000000000000',
    l_accepted,l_target_effective,l_epoch,l_generation,l_target);
  if l_accepted<>1 or l_target_effective<l_target then
    raise_application_error(-20000,'scheduled input target ignored');end if;
  l_error:=0;
  begin
    doom_api.revise_match_input(l_match,l_p0,3,'0800000000000000',
      l_accepted,l_duplicate_tic,l_epoch,l_generation,l_tic+13);
  exception when others then l_error:=sqlcode;end;
  if l_error=0 then
    raise_application_error(-20000,'out-of-window input target accepted');end if;

  for i in 1..1000 loop
    select current_tic into l_tic from doom_match where match_id=l_match;
    exit when l_tic>=greatest(l_effective0,l_effective1)+2;
    dbms_session.sleep(.01);
  end loop;
  select command_source,lower(rawtohex(ticcmd_raw)) into l_source,l_raw
    from doom_match_command where match_id=l_match and tic=l_effective0
      and player_slot=0;
  select lower(rawtohex(command_vector)) into l_vector from doom_match_tic
    where match_id=l_match and tic=l_effective0;
  if l_source<>'SAMPLED_INPUT' or l_raw<>'0800000000000000' or
     substr(l_vector,1,16)<>l_raw then
    raise_application_error(-20000,'host sampled ledger mismatch');end if;
  select command_source,lower(rawtohex(ticcmd_raw)) into l_source,l_raw
    from doom_match_command where match_id=l_match and tic=l_effective1
      and player_slot=1;
  select lower(rawtohex(command_vector)) into l_vector from doom_match_tic
    where match_id=l_match and tic=l_effective1;
  if l_source<>'SAMPLED_INPUT' or l_raw<>'00f8000000000000' or
     substr(l_vector,17,16)<>l_raw then
    raise_application_error(-20000,'guest sampled ledger mismatch');end if;

  select job_name into l_job from doom_match_worker_control where match_id=l_match;
  doom_worker_lifecycle.stop_job(
    l_job,true,'paced-input recovery gate');
  select current_tic into l_frontier from doom_match where match_id=l_match;
  select state_sha into l_frontier_state from doom_match_tic
    where match_id=l_match and tic=l_frontier;
  doom_match_worker.recover_match(l_match,180000,l_recovery);
  if l_recovery<>'ACTIVE' then raise_application_error(-20000,'paced recovery failed');end if;
  for i in 1..1000 loop
    status_;exit when l_generation=2 and l_tic>l_frontier;dbms_session.sleep(.01);
  end loop;
  if l_generation<>2 or l_tic<=l_frontier then
    raise_application_error(-20000,'paced recovery did not resume');end if;
  select count(*) into l_count from doom_match_tic
    where match_id=l_match and tic=l_frontier+1
      and previous_state_sha=l_frontier_state;
  if l_count<>1 then raise_application_error(-20000,'recovery state chain broke');end if;
  select count(*) into l_count from doom_match_tic t
    where t.match_id=l_match and t.tic>0 and t.command_vector<>(
      select utl_raw.concat(
        max(case when c.player_slot=0 then c.ticcmd_raw end),
        max(case when c.player_slot=1 then c.ticcmd_raw end),
        hextoraw(rpad('00',32,'0')))
      from doom_match_command c where c.match_id=t.match_id and c.tic=t.tic);
  if l_count<>0 then raise_application_error(-20000,'command ledger identity broke');end if;

  cleanup_;
  dbms_output.put_line('PASS P13.2-PACED-INPUT linearization/idempotency/ledger/recovery');
exception when others then rollback;cleanup_;raise;
end;
/
