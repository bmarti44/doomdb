whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimspool on serveroutput on size unlimited

declare
  c_calls constant pls_integer:=3000;
  c_window constant pls_integer:=100;
  l_wad blob;l_tables blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_frame_length number;l_frontier number:=0;l_start timestamp with time zone;
  l_window_start timestamp with time zone;l_render_start timestamp with time zone;
  l_elapsed number;l_render_elapsed number:=0;
  l_prior_per_call number:=null;l_landing_windows number:=0;

  function elapsed_ms(p_start timestamp with time zone) return number is
    d interval day to second:=systimestamp-p_start;
  begin
    return extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
  end;

  procedure load_asset(p_blob blob,p_kind varchar2) is
  begin
    l_length:=dbms_lob.getlength(p_blob);l_offset:=0;
    if p_kind='IWAD' then l_loaded:=doom_teavm_bind_allocate(l_length);
    else l_loaded:=doom_teavm_bind_table_allocate(l_length);end if;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(32767,l_length-l_offset),l_offset+1);
      if p_kind='IWAD' then
        l_loaded:=doom_teavm_bind_load(l_offset,l_chunk);
      else
        l_loaded:=doom_teavm_bind_table_load(l_offset,l_chunk);
      end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;
begin
  if sys_context('userenv','client_identifier')
      <>'OCI_RAW_FRAME_RING_300' then
    raise_application_error(-20796,'unsupported renderer warm profile');
  end if;
  doom_teavm_bind_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob into l_tables from doom_teavm_sim_source;
  load_asset(l_wad,'IWAD');load_asset(l_tables,'TABLES');
  if doom_teavm_bind_multi_init_game(2,1,3,1,1)
      not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'renderer warm init mismatch');
  end if;
  l_start:=systimestamp;l_window_start:=l_start;
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector from doom_mle_perf_vector
    where stream_name='live-dm-2026-07-23'
      and tic between 1 and c_calls order by tic
  ) loop
    l_frontier:=doom_teavm_bind_authority_step(
      2,command_.membership,command_.command_vector);
    if l_frontier<>command_.tic then
      raise_application_error(-20796,'renderer warm frontier mismatch');
    end if;
    l_render_start:=systimestamp;
    l_frame_length:=doom_teavm_bind_frame_length(0);
    l_render_elapsed:=l_render_elapsed+elapsed_ms(l_render_start);
    if l_frame_length<>64000 then
      raise_application_error(-20796,'renderer warm frame mismatch');
    end if;
    if mod(command_.tic,c_window)=0 then
      l_elapsed:=l_render_elapsed/c_window;
      dbms_output.put_line(
        'PMLE_OCI_RENDERER_WARM_WINDOW|DIAGNOSTIC_NOT_GATE|calls='||
        (command_.tic-c_window+1)||'-'||command_.tic||
        '|milliseconds_per_render='||
        to_char(l_elapsed,'FM9999990.000')||
        '|milliseconds_per_step_and_render='||
        to_char(elapsed_ms(l_window_start)/c_window,'FM9999990.000'));
      if l_prior_per_call is not null and
          l_elapsed<=l_prior_per_call*.5 then
        l_landing_windows:=l_landing_windows+1;
      end if;
      l_prior_per_call:=l_elapsed;
      l_window_start:=systimestamp;
      l_render_elapsed:=0;
    end if;
  end loop;
  if l_frontier<>c_calls then
    raise_application_error(-20796,'renderer warm corpus incomplete');
  end if;
  dbms_output.put_line(
    'PMLE_OCI_RENDERER_WARM|DIAGNOSTIC_NOT_GATE|calls='||c_calls||
    '|window='||c_window||
    '|elapsed_ms='||to_char(elapsed_ms(l_start),'FM999999990.000')||
    '|landing_windows='||l_landing_windows||
    '|verdict=MEASURE_ONLY_EXACT_STREAM_FOLLOWS');
  -- Release Java state but retain this MLE session/isolate. The following
  -- exact-stream cell reinitializes the engine without discarding any code
  -- compiled for this module.
  doom_teavm_bind_release;
end;
/
