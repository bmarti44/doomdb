set serveroutput on size unlimited
set verify off feedback off heading off pagesize 0 linesize 32767 long 1000000

-- Required SQL*Plus defines:
--   route_session, route_lineage, route_from_tic, route_to_tic,
--   route_start_sequence
declare
  l_json clob;
  l_offset number:=1;
begin
  with commands as (
    -- LOAD copies the canonical frame ledger into the new lineage while the
    -- original normalized request remains under its source lineage. Follow
    -- the copied request_id so an export includes the complete ancestry, not
    -- only commands submitted after the latest LOAD branch.
    select f.tic expected_tic,r.command_pack,
      to_number(rawtohex(utl_raw.substr(r.command_pack,24,1)),'XX') flags
    from doom_mocha_frame_ledger f
    join doom_worker_request r on r.request_id=f.request_id
    where f.session_token='&&route_session'
      and f.save_lineage='&&route_lineage'
      and r.request_status='COMMITTED'
      and f.tic between &&route_from_tic+1 and &&route_to_tic
  ), marked as (
    select c.*,case when lag(utl_raw.substr(command_pack,17,8))
      over(order by expected_tic)=utl_raw.substr(command_pack,17,8)
      then 0 else 1 end changed from commands c
  ), grouped as (
    select m.*,sum(changed) over(order by expected_tic) run_no from marked m
  ), runs as (
    select min(expected_tic) first_tic,count(*) repeat_count,
      min(command_pack) command_pack,min(flags) flags
    from grouped group by run_no
  ), route as (
    select json_arrayagg(json_object(
      'repeat' value repeat_count,
      'command' value json_object(
        'turn' value case when to_number(rawtohex(utl_raw.substr(command_pack,17,1)),'XX')>=128
          then to_number(rawtohex(utl_raw.substr(command_pack,17,1)),'XX')-256
          else to_number(rawtohex(utl_raw.substr(command_pack,17,1)),'XX') end,
        'forward' value case when to_number(rawtohex(utl_raw.substr(command_pack,18,1)),'XX')>=128
          then to_number(rawtohex(utl_raw.substr(command_pack,18,1)),'XX')-256
          else to_number(rawtohex(utl_raw.substr(command_pack,18,1)),'XX') end,
        'strafe' value case when to_number(rawtohex(utl_raw.substr(command_pack,19,1)),'XX')>=128
          then to_number(rawtohex(utl_raw.substr(command_pack,19,1)),'XX')-256
          else to_number(rawtohex(utl_raw.substr(command_pack,19,1)),'XX') end,
        'run' value to_number(rawtohex(utl_raw.substr(command_pack,20,1)),'XX'),
        'fire' value to_number(rawtohex(utl_raw.substr(command_pack,21,1)),'XX'),
        'use' value to_number(rawtohex(utl_raw.substr(command_pack,22,1)),'XX'),
        'weapon' value to_number(rawtohex(utl_raw.substr(command_pack,23,1)),'XX'),
        'pause' value bitand(flags,1),
        'automap' value bitand(flags,2)/2,
        'menu' value case when bitand(flags,4)=4 then 'OPTIONS' else 'NONE' end,
        'cheat' value ''
        returning clob) returning clob)
      order by first_tic returning clob) runs_json,
      sum(repeat_count) command_count from runs
  )
  select json_serialize(json_object(
    'envelopeVersion' value 2,
    'startSequence' value &&route_start_sequence,
    'commandCount' value command_count,
    'runs' value runs_json format json returning clob) returning clob)
    into l_json from route;
  dbms_output.put_line('BASE64:');
  while l_offset<=dbms_lob.getlength(l_json) loop
    -- SQL*Plus/DBMS_OUTPUT inserts a newline between chunks. Base64 each
    -- independently aligned 18,000-byte slice so those newlines are harmless
    -- even when the source boundary falls inside a JSON string token.
    dbms_output.put_line(utl_raw.cast_to_varchar2(utl_encode.base64_encode(
      utl_raw.cast_to_raw(dbms_lob.substr(l_json,18000,l_offset)))));
    l_offset:=l_offset+18000;
  end loop;
end;
/
