whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_mode varchar2(16);l_skill number;l_episode number;l_map number;l_max number;
  l_members number;l_ready_count number;l_requester number;l_epoch number;
  l_generation number;l_tic number;l_accepted number;l_ready number;l_payload blob;
  l_worker_mode varchar2(16);l_recovery_status varchar2(16);
  l_job varchar2(64);l_count number;l_bitmap varchar2(2);l_source varchar2(16);
  procedure status_ is
  begin
    doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
      l_max,l_members,l_ready_count,l_requester,l_epoch,l_generation,l_tic,
      l_worker_mode,l_recovery_status);
  end;
  procedure cleanup_ is
  begin
    if l_match is null then return;end if;
    begin
      select job_name,generation into l_job,l_generation
        from doom_match_worker_control where match_id=l_match;
      doom_match_worker.stop_match(l_match,l_generation);dbms_session.sleep(.2);
    exception when no_data_found then null;end;
    for i in 1..900 loop
      select count(*) into l_count from doom_mle_warm_slot
        where assigned_match=l_match;
      exit when l_count=0;
      dbms_session.sleep(.1);
    end loop;
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
  for i in 1..1000 loop
    status_;
    exit when l_tic>=1;dbms_session.sleep(.01);
  end loop;
  if l_tic<>1 then raise_application_error(-20000,'left tic timeout');end if;
  select rawtohex(membership_bitmap),rawtohex(neutral_bitmap) into l_bitmap,l_join
    from doom_match_tic where match_id=l_match and tic=1;
  select command_source into l_source from doom_match_command
    where match_id=l_match and tic=1 and player_slot=1;
  if l_bitmap<>'01' or l_join not in('02','03') or l_source<>'NEUTRAL_LEFT' then
    raise_application_error(-20000,'left frontier mismatch membership='||
      l_bitmap||' neutral='||l_join||' source='||l_source);
  end if;

  doom_api.leave_match(l_match,l_p0,l_state);
  if l_state<>'FINISHED' then raise_application_error(-20000,'host finish');end if;
  doom_api.leave_match(l_match,l_p0,l_state);
  if l_state<>'FINISHED' then raise_application_error(-20000,'host finish retry');end if;
  select count(*) into l_count from doom_match
    where match_id=l_match and match_state='FINISHED'
      and expires_at>(localtimestamp at time zone 'UTC')+
        numtodsinterval(4,'MINUTE');
  if l_count<>1 then
    raise_application_error(-20000,'host leave terminal evidence retention');
  end if;
  for i in 1..900 loop
    select count(*) into l_count from doom_mle_warm_slot
      where assigned_match=l_match;
    exit when l_count=0;
    dbms_session.sleep(.1);
  end loop;
  if l_count<>0 then raise_application_error(-20000,'host leave retained slot');end if;
  cleanup_;
  dbms_output.put_line('PASS P13.2-ACTIVE-LEAVE boundary=1 membership=01 neutral-left host-release finish');
exception when others then rollback;cleanup_;raise;
end;
/
