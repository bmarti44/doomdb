whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited

declare
  l_cpu varchar2(128);l_plan varchar2(128);l_cpu_managed varchar2(16);
  l_pdb_cpu varchar2(128):='UNAVAILABLE';l_limit varchar2(128):='UNAVAILABLE';
  l_running_limit varchar2(128):='UNAVAILABLE';l_pdb_plan varchar2(128):='UNAVAILABLE';
begin
  select value into l_cpu from v$parameter where name='cpu_count';
  select coalesce(max(name),'NONE'),coalesce(max(cpu_managed),'OFF')
    into l_plan,l_cpu_managed from v$rsrc_plan where is_top_plan='TRUE';
  begin
    execute immediate q'~select coalesce(to_char(num_cpus),'NULL'),
      coalesce(to_char(cpu_utilization_limit),'NULL'),
      coalesce(to_char(running_sessions_limit),'NULL'),coalesce(plan_name,'NULL')
      from v$rsrcpdbmetric
      where con_id=sys_context('USERENV','CON_ID')~'
      into l_pdb_cpu,l_limit,l_running_limit,l_pdb_plan;
  exception when no_data_found then
    l_pdb_cpu:='NONE';l_limit:='NONE';l_running_limit:='NONE';l_pdb_plan:='NONE';
  when others then
    if sqlcode<>-942 then raise;end if;
  end;
  dbms_output.put_line('PMLE_ENVIRONMENT|cpu_count='||l_cpu||
    '|resource_plan='||l_plan||'|cpu_managed='||l_cpu_managed||
    '|pdb_cpu_count='||l_pdb_cpu||'|pdb_utilization_limit='||l_limit||
    '|pdb_running_sessions_limit='||l_running_limit||'|pdb_plan='||l_pdb_plan);
end;
/
