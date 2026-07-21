-- Idempotent live upgrade for the feature-flagged P13 paced-input worker.
declare
  l_count number;
begin
  select count(*) into l_count from user_tab_columns
    where table_name='DOOM_MATCH_WORKER_CONTROL' and column_name='WORKER_MODE';
  if l_count=0 then
    execute immediate q'[alter table doom_match_worker_control add (
      worker_mode varchar2(16) default 'LOCKSTEP' not null)]';
  end if;
  select count(*) into l_count from user_constraints
    where constraint_name='DOOM_MATCH_WORKER_MODE_CK';
  if l_count=0 then
    execute immediate q'[alter table doom_match_worker_control add constraint
      doom_match_worker_mode_ck check(worker_mode in('LOCKSTEP','PACED_INPUT'))]';
  end if;
end;
/

declare
  l_search varchar2(4000);
begin
  execute immediate 'alter table doom_match_command modify (command_source varchar2(24))';
  select search_condition_vc into l_search from user_constraints
    where constraint_name='DOOM_MATCH_COMMAND_SOURCE_CK';
  if instr(l_search,'SAMPLED_INPUT')=0 then
    execute immediate 'alter table doom_match_command drop constraint doom_match_command_source_ck';
    execute immediate q'[alter table doom_match_command add constraint
      doom_match_command_source_ck check(command_source in(
        'SUBMITTED','SAMPLED_INPUT','NEUTRAL_INITIAL',
        'NEUTRAL_DISCONNECTED','NEUTRAL_DEADLINE','NEUTRAL_LEFT'))]';
  end if;
end;
/

merge into doom_config d
using (select 'MATCH_WORKER_MODE' config_key, cast(null as number) number_value,
              'LOCKSTEP' text_value from dual) s
on (d.config_key=s.config_key)
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,s.text_value);

commit;
