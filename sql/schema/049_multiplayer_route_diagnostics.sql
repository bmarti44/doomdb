-- Idempotent upgrade for installations created before private multiplayer
-- route diagnostics were added. Fresh installs already contain these columns.
declare
  procedure add_column(p_name varchar2,p_definition varchar2) is
    l_count number;
  begin
    select count(*) into l_count from user_tab_columns
      where table_name='DOOM_MATCH_WORKER_CONTROL' and column_name=p_name;
    if l_count=0 then
      execute immediate 'alter table doom_match_worker_control add ('||
        lower(p_name)||' '||p_definition||')';
    end if;
  end;
begin
  add_column('ROUTE_DIAGNOSTICS','number(1) default 0 not null');
  add_column('CHECKPOINT_TEST_HOOK','number(1) default 0 not null');
  add_column('ROUTE_STATUS_TIC','number(12)');
  add_column('ROUTE_STATUS','varchar2(4000)');
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_constraints
    where constraint_name='DOOM_MATCH_CHECKPOINT_HOOK_CK';
  if l_count=0 then
    execute immediate q'[alter table doom_match_worker_control add constraint
      doom_match_checkpoint_hook_ck check(checkpoint_test_hook in(0,1))]';
  end if;
end;
/

begin
  execute immediate q'~create table doom_match_checkpoint_probe (
    match_id varchar2(32) not null,
    tic number(12) not null,
    generation number(12) not null,
    previous_checkpoint_tic number(12) not null,
    checkpoint_distance number(12) not null,
    awake_monsters number(12) not null,
    checkpoint_decision varchar2(16) not null,
    observed_at timestamp with time zone default
      (localtimestamp at time zone 'UTC') not null,
    constraint doom_match_checkpoint_probe_pk primary key(match_id,tic),
    constraint doom_match_checkpoint_probe_match_fk foreign key(match_id)
      references doom_match(match_id) on delete cascade,
    constraint doom_match_checkpoint_probe_decision_ck check(
      checkpoint_decision in('LOW_AWAKE','FORCED_MAX','DEFER_HIGH'))
  )~';
exception when others then if sqlcode<>-955 then raise;end if;
end;
/

begin
  execute immediate q'~create table doom_route_trace (
    session_token varchar2(32) not null,
    tic number(12) not null,
    route_status varchar2(4000) not null,
    constraint doom_route_trace_pk primary key(session_token,tic),
    constraint doom_route_trace_session_fk foreign key(session_token)
      references game_sessions(session_token) on delete cascade)~';
exception when others then if sqlcode<>-955 then raise;end if;
end;
/

begin
  execute immediate q'~create table doom_match_route_trace (
    match_id varchar2(32) not null,
    tic number(12) not null,
    route_status varchar2(4000) not null,
    constraint doom_match_route_trace_pk primary key(match_id,tic),
    constraint doom_match_route_trace_match_fk foreign key(match_id)
      references doom_match(match_id) on delete cascade)~';
exception when others then if sqlcode<>-955 then raise;end if;
end;
/

commit;
