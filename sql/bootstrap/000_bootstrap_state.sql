declare
  table_exists number;
begin
  select count(*)
    into table_exists
    from user_tables
   where table_name = 'DOOM_BOOTSTRAP_STATE';
  if table_exists = 0 then
    execute immediate q'[
      create table doom_bootstrap_state (
        component varchar2(30) primary key,
        semantic_version number(10) not null check (semantic_version >= 1)
      )
    ]';
  end if;
end;
/

merge into doom_bootstrap_state target
using (select 'P1_BOOTSTRAP' component, 1 semantic_version from dual) source
   on (target.component = source.component)
when matched then update set target.semantic_version = source.semantic_version
when not matched then insert (component, semantic_version)
values (source.component, source.semantic_version);

commit;
