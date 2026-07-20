-- Idempotent live upgrade for the opt-in, non-public route-authoring mirror.
-- The default stays off, so production tics do not write diagnostic text.
declare
  procedure add_column(p_name varchar2,p_ddl varchar2) is
    l_count number;
  begin
    select count(*) into l_count from user_tab_columns
      where table_name='DOOM_WORKER_CONTROL' and column_name=p_name;
    if l_count=0 then execute immediate p_ddl;end if;
  end;
begin
  add_column('ROUTE_DIAGNOSTICS',
    'alter table doom_worker_control add (route_diagnostics number(1) default 0 not null)');
  add_column('ROUTE_STATUS_TIC',
    'alter table doom_worker_control add (route_status_tic number(12))');
  add_column('ROUTE_STATUS',
    'alter table doom_worker_control add (route_status varchar2(4000))');
end;
/

commit;
