-- Upgrade an existing retained-standby control row for off-hot-path DMC1
-- creation. Clean installs receive the same columns from 048.
declare
  l_count number;
  procedure add_column(p_name varchar2,p_ddl varchar2) is
  begin
    select count(*) into l_count from user_tab_columns
      where table_name='DOOM_MATCH_STANDBY_CONTROL'
        and column_name=upper(p_name);
    if l_count=0 then execute immediate p_ddl;end if;
  end;
begin
  add_column('checkpoint_request_tic',
    'alter table doom_match_standby_control add checkpoint_request_tic number(12)');
  add_column('checkpoint_status',
    q'~alter table doom_match_standby_control add checkpoint_status varchar2(16) default 'IDLE' not null~');
  add_column('checkpoint_error',
    'alter table doom_match_standby_control add checkpoint_error varchar2(2000)');
  add_column('checkpoint_completed_tic',
    'alter table doom_match_standby_control add checkpoint_completed_tic number(12)');
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_constraints
    where table_name='DOOM_MATCH_STANDBY_CONTROL'
      and constraint_name='DOOM_MATCH_STANDBY_CHECKPOINT_CK';
  if l_count=0 then
    execute immediate q'~
      alter table doom_match_standby_control add constraint
        doom_match_standby_checkpoint_ck check(
          checkpoint_status in('IDLE','QUEUED','PROCESSING','FAILED') and
          (checkpoint_request_tic is null or checkpoint_request_tic>=0) and
          (checkpoint_completed_tic is null or checkpoint_completed_tic>=0))
    ~';
  end if;
end;
/

commit;
