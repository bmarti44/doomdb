-- Trusted worker-only adapter for a byte-exact retained history envelope.
-- The legacy DOOM_CAPTURE_TIC_BLOB remains the independent SQL oracle.
create or replace procedure doom_capture_retained_tic(
  p_session in varchar2,p_lineage in varchar2,p_tic in number,
  p_frontier in number,p_command_sha in varchar2,p_event_sha in varchar2,
  p_state_sha in varchar2,p_frame_sha in varchar2,p_snapshot_sha in varchar2,
  p_snapshot_blob in blob
) authid definer is
  c_bad_history constant pls_integer:=-20891;
  l_lineage varchar2(64);l_tic number;l_frontier number;l_interval number;
  l_command_sha varchar2(64);l_event_sha varchar2(64);l_first number;
  l_state_sha varchar2(64);l_frame_sha varchar2(64);
  l_snapshot_locator blob;
begin
  if p_session is null or p_lineage is null or p_tic is null or
     p_frontier is null or p_snapshot_blob is null or
     not regexp_like(p_lineage,'^[0-9a-f]{64}$') or
     not regexp_like(p_command_sha,'^[0-9a-f]{64}$') or
     not regexp_like(p_event_sha,'^[0-9a-f]{64}$') or
     not regexp_like(p_state_sha,'^[0-9a-f]{64}$') or
     not regexp_like(p_frame_sha,'^[0-9a-f]{64}$') or
     not regexp_like(p_snapshot_sha,'^[0-9a-f]{64}$') then
    raise_application_error(c_bad_history,'retained capture input');
  end if;
  select save_lineage,current_tic,last_command_seq
    into l_lineage,l_tic,l_frontier from game_sessions
    where session_token=p_session for update;
  if l_lineage<>p_lineage or l_tic<>p_tic or l_frontier<>p_frontier then
    raise_application_error(c_bad_history,'retained capture frontier');
  end if;
  select command_sha,event_sha into l_command_sha,l_event_sha
    from history_heads where session_token=p_session and lineage=p_lineage;
  if l_command_sha<>p_command_sha or l_event_sha<>p_event_sha then
    raise_application_error(c_bad_history,'retained capture heads');
  end if;
  select state_sha,frame_sha into l_state_sha,l_frame_sha from tic_commands
    where session_token=p_session and lineage=p_lineage and tic=p_tic
      and command_ordinal=0 and command_seq=p_frontier;
  if l_state_sha<>p_state_sha or l_frame_sha<>p_frame_sha then
    raise_application_error(c_bad_history,'retained capture state/frame');
  end if;
  select number_value into l_interval from doom_config
    where config_key='HISTORY_SNAPSHOT_INTERVAL';
  if l_interval<>trunc(l_interval) or l_interval<1 or mod(p_tic,l_interval)<>0 then
    raise_application_error(c_bad_history,'retained capture cadence');
  end if;
  select coalesce(min(command_seq),p_frontier+1) into l_first from tic_commands
    where session_token=p_session and lineage=p_lineage;
  insert into state_history(session_token,lineage,tic,first_command_seq,
    last_command_seq,state_sha,command_sha,event_sha,frame_sha,snapshot_sha,
    snapshot_reason,snapshot_blob)
  values(p_session,p_lineage,p_tic,l_first,p_frontier,p_state_sha,p_command_sha,
    p_event_sha,p_frame_sha,p_snapshot_sha,'INTERVAL',empty_blob())
  returning snapshot_blob into l_snapshot_locator;
  dbms_lob.copy(l_snapshot_locator,p_snapshot_blob,
    dbms_lob.getlength(p_snapshot_blob),1,1);
exception
  when dup_val_on_index then null;
  when no_data_found then
    raise_application_error(c_bad_history,'retained capture owner');
end;
/
