set serveroutput on size unlimited
set verify off feedback off heading off pagesize 0 linesize 32767 long 1000000

declare
  l_session varchar2(32);
  l_json clob;
  l_offset number:=1;
begin
  select session_token into l_session from (
    select session_token from game_sessions
      where game_mode in('GAME','INTERMISSION') and current_tic>0
      order by created_at desc,current_tic desc
  ) where rownum=1;

  with commands as (
    select r.expected_command_seq+1 sequence_no,r.command_pack,
      to_number(rawtohex(utl_raw.substr(r.command_pack,24,1)),'XX') flags
    from doom_worker_request r
    where r.session_token=l_session and r.request_status='COMMITTED'
      and r.expected_command_seq>=762
  ), bounded as (
    select c.* from commands c
    where c.sequence_no < nvl((select min(sequence_no) from commands
      where floor(flags/8)>0),999999999999)
  ), marked as (
    select b.*,case when lag(utl_raw.substr(command_pack,17,8))
      over(order by sequence_no)=utl_raw.substr(command_pack,17,8)
      then 0 else 1 end changed from bounded b
  ), grouped as (
    select m.*,sum(changed) over(order by sequence_no) run_no from marked m
  ), runs as (
    select min(sequence_no) first_sequence,max(sequence_no) last_sequence,
      count(*) repeat_count,min(command_pack) command_pack,min(flags) flags
    from grouped group by run_no
  )
  select json_serialize(json_arrayagg(json_object(
    'firstSequence' value first_sequence,
    'lastSequence' value last_sequence,
    'repeat' value repeat_count,
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
    'menu' value case when bitand(flags,4)=4 then 'OPTIONS' else 'NONE' end
    returning clob) order by first_sequence returning clob) returning clob)
    into l_json from runs;
  dbms_output.put_line('SESSION '||l_session);
  while l_offset<=dbms_lob.getlength(l_json) loop
    dbms_output.put_line(dbms_lob.substr(l_json,30000,l_offset));
    l_offset:=l_offset+30000;
  end loop;
end;
/
