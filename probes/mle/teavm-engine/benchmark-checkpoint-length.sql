whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 serveroutput on size unlimited

declare
  l_wad blob;l_pack blob;l_chunk raw(32767);l_length pls_integer;
  l_offset pls_integer;l_loaded number;l_state varchar2(32767);
  l_started timestamp with time zone;l_first_ms number;l_repeat_ms number;
  l_tic number;l_commands raw(32):=hextoraw(rpad('00',64,'00'));
  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;
begin
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);
  l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_state:=doom_teavm_sim_multi_init_game(2,0,3,1,1);
  for i in 1..32 loop
    l_tic:=doom_teavm_sim_authority_step(2,3,l_commands);
    if l_tic<>i then raise_application_error(-20796,'checkpoint benchmark tic');end if;
  end loop;
  l_started:=systimestamp;l_length:=doom_teavm_sim_checkpoint_length;
  l_first_ms:=elapsed_ms(systimestamp-l_started);
  l_started:=systimestamp;
  if doom_teavm_sim_checkpoint_length<>l_length then
    raise_application_error(-20796,'checkpoint length drift');
  end if;
  l_repeat_ms:=elapsed_ms(systimestamp-l_started);
  dbms_output.put_line('PMLE_CHECKPOINT_LENGTH|PASS|tic=32|bytes='||l_length||
    '|first_ms='||round(l_first_ms,3)||
    '|repeated_ms='||round(l_repeat_ms,3));
  doom_teavm_sim_release;
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  raise;
end;
/
