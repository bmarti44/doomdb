whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimspool on serveroutput on size unlimited

declare
  c_offset constant pls_integer:=100;
  c_warmup constant pls_integer:=30;
  c_samples constant pls_integer:=100;
  c_frame_bytes constant pls_integer:=64000;
  type numbers is table of number index by pls_integer;
  l_count_only numbers;
  l_capture numbers;
  l_raster numbers;
  l_commands numbers;
  l_wad blob;
  l_tables blob;
  l_frame blob;
  l_normal blob;
  l_chunk raw(32767);
  l_length pls_integer;
  l_offset pls_integer;
  l_loaded number;
  l_frontier number;
  l_started timestamp with time zone;
  l_normal_sha varchar2(64);
  l_candidate_sha varchar2(64);
  l_exact number:=0;

  function elapsed_ms(p_started timestamp with time zone) return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin
    return extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000;
  end;

  procedure sort_values(p_values in out nocopy numbers) is l_swap number;
  begin
    for left_ in 1..c_samples-1 loop
      for right_ in left_+1..c_samples loop
        if p_values(right_)<p_values(left_) then
          l_swap:=p_values(left_);p_values(left_):=p_values(right_);
          p_values(right_):=l_swap;
        end if;
      end loop;
    end loop;
  end;

  procedure initialize_engine is
  begin
    begin doom_teavm_sim_release;exception when others then null;end;
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);
    l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    select table_pack_blob into l_tables from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_tables);
    l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_tables,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    if doom_teavm_sim_multi_init_game(2,1,3,1,1)
        not like 'state=multiplayer-initialized|gametic=0|%' then
      raise_application_error(-20796,'bisection initialization mismatch');
    end if;
    l_frontier:=0;
  end;

  procedure append_frame(
      p_kind varchar2,p_target in out nocopy blob) is
  begin
    dbms_lob.trim(p_target,0);l_offset:=0;
    while l_offset<c_frame_bytes loop
      l_length:=least(32767,c_frame_bytes-l_offset);
      if p_kind='NORMAL' then
        l_chunk:=doom_teavm_sim_frame_chunk(l_offset,l_length);
      else
        l_chunk:=doom_teavm_live_row_chunk(l_offset,l_length);
      end if;
      dbms_lob.writeappend(p_target,l_length,l_chunk);
      l_offset:=l_offset+l_length;
    end loop;
  end;

  procedure run_count_only is l_sample pls_integer;
  begin
    initialize_engine;
    for command_ in (
      select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
        command_vector from doom_mle_perf_vector
      where stream_name='live-dm-2026-07-23'
        and tic<=c_offset+c_warmup+c_samples order by tic
    ) loop
      l_frontier:=doom_teavm_sim_authority_step(
        2,command_.membership,command_.command_vector);
      if command_.tic>c_offset then
        l_started:=systimestamp;
        if doom_teavm_live_count_only(0)<>c_frame_bytes then
          raise_application_error(-20796,'count-only frame length');
        end if;
        if command_.tic>c_offset+c_warmup then
          l_sample:=command_.tic-c_offset-c_warmup;
          l_count_only(l_sample):=elapsed_ms(l_started);
        end if;
      end if;
    end loop;
  end;

  procedure run_split is l_sample pls_integer;l_count number;
  begin
    initialize_engine;
    for command_ in (
      select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
        command_vector from doom_mle_perf_vector
      where stream_name='live-dm-2026-07-23'
        and tic<=c_offset+c_warmup+c_samples order by tic
    ) loop
      l_frontier:=doom_teavm_sim_authority_step(
        2,command_.membership,command_.command_vector);
      if command_.tic>c_offset then
        l_started:=systimestamp;
        l_count:=doom_teavm_live_capture_commands(0);
        if command_.tic>c_offset+c_warmup then
          l_sample:=command_.tic-c_offset-c_warmup;
          l_capture(l_sample):=elapsed_ms(l_started);
          l_commands(l_sample):=l_count;
        end if;
        l_started:=systimestamp;
        if doom_teavm_live_raster_only<>c_frame_bytes then
          raise_application_error(-20796,'raster-only frame length');
        end if;
        if command_.tic>c_offset+c_warmup then
          l_raster(l_sample):=elapsed_ms(l_started);
          if l_sample in (1,50,100) then
            if doom_teavm_live_prepare_row<>c_frame_bytes then
              raise_application_error(-20796,'bisection row prepare');
            end if;
            append_frame('CANDIDATE',l_frame);
            l_candidate_sha:=lower(rawtohex(
              dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256)));
            if doom_teavm_sim_frame_length(0)<>c_frame_bytes then
              raise_application_error(-20796,'bisection normal frame');
            end if;
            append_frame('NORMAL',l_normal);
            l_normal_sha:=lower(rawtohex(
              dbms_crypto.hash(l_normal,dbms_crypto.hash_sh256)));
            if l_candidate_sha<>l_normal_sha then
              raise_application_error(-20796,'bisection exactness mismatch');
            end if;
            l_exact:=l_exact+1;
            dbms_output.put_line(
              'PMLE_LIVE_BISECTION_EQUIVALENCE|PASS|tic='||l_frontier||
              '|sha256='||l_normal_sha);
          end if;
        end if;
      end if;
    end loop;
  end;
begin
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  dbms_lob.createtemporary(l_normal,true,dbms_lob.call);
  run_count_only;
  run_split;
  if l_exact<>3 then
    raise_application_error(-20796,'bisection exact sample count');
  end if;
  sort_values(l_count_only);sort_values(l_capture);sort_values(l_raster);
  sort_values(l_commands);
  dbms_output.put_line(
    'PMLE_LIVE_COMMAND_BISECTION|DIAGNOSTIC_NOT_GATE'||
    '|window=PEAK_AWAKE|offset='||c_offset||
    '|samples='||c_samples||'|warmup='||c_warmup||
    '|exact_samples='||l_exact||
    '|commands_p50='||l_commands(50)||'|commands_p95='||l_commands(95)||
    '|count_only_p50_ms='||
      to_char(l_count_only(50),'FM9999990.000')||
    '|count_only_p95_ms='||
      to_char(l_count_only(95),'FM9999990.000')||
    '|capture_p50_ms='||to_char(l_capture(50),'FM9999990.000')||
    '|capture_p95_ms='||to_char(l_capture(95),'FM9999990.000')||
    '|raster_p50_ms='||to_char(l_raster(50),'FM9999990.000')||
    '|raster_p95_ms='||to_char(l_raster(95),'FM9999990.000')||
    '|capture_minus_count_p50_ms='||
      to_char(l_capture(50)-l_count_only(50),'FM9999990.000')||
    '|capture_minus_count_p95_ms='||
      to_char(l_capture(95)-l_count_only(95),'FM9999990.000'));
  doom_teavm_sim_release;
  dbms_lob.freetemporary(l_frame);dbms_lob.freetemporary(l_normal);
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  begin
    if dbms_lob.istemporary(l_frame)=1 then dbms_lob.freetemporary(l_frame);end if;
    if dbms_lob.istemporary(l_normal)=1 then
      dbms_lob.freetemporary(l_normal);
    end if;
  exception when others then null;
  end;
  raise;
end;
/
