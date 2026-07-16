whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited feedback off timing off

variable profiler_run number

declare
  l_session varchar2(32);
  payload blob;
  result_code binary_integer;

  function command_doc(command_seq number) return clob is
  begin
    return to_clob('{"v":1,"commands":[{"turn":' ||
      case when mod(command_seq, 2) = 0 then '1' else '-1' end ||
      ',"forward":0,"strafe":0,"run":0,"fire":0,"use":0,' ||
      '"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":' ||
      command_seq || '}]}');
  end command_doc;
begin
  doom_api.new_game(3, l_session, payload);
  for command_seq in 1 .. 30 loop
    doom_tic_tx.apply_batch(l_session, command_doc(command_seq), payload);
    commit;
  end loop;

  result_code := dbms_profiler.start_profiler(
    'T12.0 render-free simulation',
    '30 committed unique turn tics after 30 warmups',
    :profiler_run
  );
  if result_code <> 0 then
    raise_application_error(-20000, 'DBMS_PROFILER start failed: ' || result_code);
  end if;

  for command_seq in 31 .. 60 loop
    doom_tic_tx.apply_batch(l_session, command_doc(command_seq), payload);
    commit;
  end loop;

  result_code := dbms_profiler.stop_profiler;
  if result_code <> 0 then
    raise_application_error(-20001, 'DBMS_PROFILER stop failed: ' || result_code);
  end if;
  result_code := dbms_profiler.flush_data;
  if result_code <> 0 then
    raise_application_error(-20002, 'DBMS_PROFILER flush failed: ' || result_code);
  end if;

  delete from game_sessions where session_token = l_session;
  commit;
  dbms_output.put_line('PROFILER_RUN=' || :profiler_run);
exception
  when others then
    result_code := dbms_profiler.stop_profiler;
    rollback;
    if l_session is not null then
      delete from game_sessions where session_token = l_session;
      commit;
    end if;
    raise;
end;
/

column unit_name format a30
column source_text format a110
set linesize 220 pagesize 100

select *
from (
  select u.unit_name,
    d.line#,
    d.total_occur,
    round(d.total_time / 1e6, 3) total_ms,
    substr(trim(s.text), 1, 110) source_text
  from plsql_profiler_data d
  join plsql_profiler_units u
    on u.runid = d.runid and u.unit_number = d.unit_number
  left join user_source s
    on s.name = u.unit_name and s.type = u.unit_type and s.line = d.line#
  where d.runid = :profiler_run
    and d.total_occur > 0
  order by d.total_time desc
)
where rownum <= 100;

select 'PROFILE_TOTAL_MS=' || round(run_total_time / 1e6, 3)
from plsql_profiler_runs
where runid = :profiler_run;

exit
