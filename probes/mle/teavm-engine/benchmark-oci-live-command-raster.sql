whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimspool on serveroutput on size unlimited

declare
  c_frame_bytes constant pls_integer:=64000;
  c_samples constant pls_integer:=300;
  c_warmup constant pls_integer:=30;
  type numbers is table of number index by pls_integer;
  type hashes is table of varchar2(64) index by pls_integer;

  l_step numbers;
  l_render numbers;
  l_egress numbers;
  l_pipeline numbers;
  l_commands numbers;
  l_seen hashes;
  l_wad blob;
  l_tables blob;
  l_frame blob;
  l_normal blob;
  l_chunk raw(32767);
  l_length pls_integer;
  l_offset pls_integer;
  l_loaded number;
  l_frontier number;
  l_step_started timestamp with time zone;
  l_stage_started timestamp with time zone;
  l_pipeline_started timestamp with time zone;
  l_tick_started number;
  l_step_ms number;
  l_render_ms number;
  l_egress_ms number;
  l_pipeline_ms number;
  l_tick_ms number;
  l_suspects number;
  l_unique number;
  l_frame_sha varchar2(64);
  l_normal_sha varchar2(64);
  l_row_major_sha varchar2(64);

  function elapsed_ms(p_started timestamp with time zone) return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin
    return extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000;
  end;

  procedure sort_values(p_values in out nocopy numbers) is
    l_swap number;
  begin
    for left_ in 1..c_samples-1 loop
      for right_ in left_+1..c_samples loop
        if p_values(right_)<p_values(left_) then
          l_swap:=p_values(left_);
          p_values(left_):=p_values(right_);
          p_values(right_):=l_swap;
        end if;
      end loop;
    end loop;
  end;

  procedure load_assets_and_initialize is
  begin
    begin doom_teavm_sim_release;exception when others then null;end;
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);
    l_loaded:=doom_teavm_sim_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'live raster IWAD short load');
      end if;
    end loop;
    select table_pack_blob into l_tables from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_tables);
    l_loaded:=doom_teavm_sim_table_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_tables,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'live raster table short load');
      end if;
    end loop;
    if doom_teavm_sim_multi_init_game(2,1,3,1,1)
        not like 'state=multiplayer-initialized|gametic=0|%' then
      raise_application_error(-20796,'live raster initialization mismatch');
    end if;
  end;

  procedure append_captured(p_row_major boolean,p_target in out nocopy blob) is
  begin
    dbms_lob.trim(p_target,0);
    l_offset:=0;
    while l_offset<c_frame_bytes loop
      l_length:=least(32767,c_frame_bytes-l_offset);
      if p_row_major then
        l_chunk:=doom_teavm_live_row_chunk(l_offset,l_length);
      else
        l_chunk:=doom_teavm_live_capture_chunk(l_offset,l_length);
      end if;
      if utl_raw.length(l_chunk)<>l_length then
        raise_application_error(-20796,'live raster captured short chunk');
      end if;
      dbms_lob.writeappend(p_target,l_length,l_chunk);
      l_offset:=l_offset+l_length;
    end loop;
  end;

  procedure append_normal(p_target in out nocopy blob) is
  begin
    dbms_lob.trim(p_target,0);
    l_offset:=0;
    while l_offset<c_frame_bytes loop
      l_length:=least(32767,c_frame_bytes-l_offset);
      l_chunk:=doom_teavm_sim_frame_chunk(l_offset,l_length);
      if utl_raw.length(l_chunk)<>l_length then
        raise_application_error(-20796,'live raster normal short chunk');
      end if;
      dbms_lob.writeappend(p_target,l_length,l_chunk);
      l_offset:=l_offset+l_length;
    end loop;
  end;

  function sum_pipeline return number;

  procedure run_window(p_name varchar2,p_offset pls_integer) is
    l_sample pls_integer;
    l_expected_tic pls_integer;
    l_exact number:=0;
    l_command_min number:=999999;
    l_command_max number:=0;
    l_duplicate boolean;
  begin
    l_step.delete;l_render.delete;l_egress.delete;l_pipeline.delete;
    l_commands.delete;l_seen.delete;
    l_frontier:=0;l_suspects:=0;l_unique:=0;
    load_assets_and_initialize;
    for command_ in (
      select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
        command_vector
      from doom_mle_perf_vector
      where stream_name='live-dm-2026-07-23'
        and tic<=p_offset+c_warmup+c_samples
      order by tic
    ) loop
      if command_.tic<>l_frontier+1 then
        raise_application_error(-20796,'live raster command stream gap');
      end if;
      if command_.tic<=p_offset then
        l_frontier:=doom_teavm_sim_authority_step(
          2,command_.membership,command_.command_vector);
        continue;
      end if;
      l_pipeline_started:=systimestamp;
      l_tick_started:=dbms_utility.get_time;
      l_step_started:=l_pipeline_started;
      l_frontier:=doom_teavm_sim_authority_step(
        2,command_.membership,command_.command_vector);
      l_step_ms:=elapsed_ms(l_step_started);

      l_stage_started:=systimestamp;
      l_length:=doom_teavm_live_capture_length(0);
      l_render_ms:=elapsed_ms(l_stage_started);
      if l_length<>c_frame_bytes then
        raise_application_error(-20796,'live raster frame length mismatch');
      end if;

      l_stage_started:=systimestamp;
      append_captured(false,l_frame);
      l_egress_ms:=elapsed_ms(l_stage_started);
      l_pipeline_ms:=elapsed_ms(l_pipeline_started);
      l_tick_ms:=(dbms_utility.get_time-l_tick_started)*10;
      if abs(l_pipeline_ms-l_tick_ms)>30 then
        l_suspects:=l_suspects+1;
      end if;

      if command_.tic>p_offset+c_warmup then
        l_sample:=command_.tic-p_offset-c_warmup;
        l_step(l_sample):=l_step_ms;
        l_render(l_sample):=l_render_ms;
        l_egress(l_sample):=l_egress_ms;
        l_pipeline(l_sample):=l_pipeline_ms;
        l_commands(l_sample):=doom_teavm_live_capture_count;
        l_command_min:=least(l_command_min,l_commands(l_sample));
        l_command_max:=greatest(l_command_max,l_commands(l_sample));
        l_frame_sha:=lower(rawtohex(
          dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256)));
        l_duplicate:=false;
        if l_unique>0 then
          for prior_ in 1..l_unique loop
            if l_seen(prior_)=l_frame_sha then
              l_duplicate:=true;
              exit;
            end if;
          end loop;
        end if;
        if not l_duplicate then
          l_unique:=l_unique+1;
          l_seen(l_unique):=l_frame_sha;
        end if;

        if l_sample in (1,150,300) then
          if doom_teavm_live_prepare_row<>c_frame_bytes then
            raise_application_error(-20796,'live raster row-major prepare');
          end if;
          append_captured(true,l_frame);
          l_row_major_sha:=lower(rawtohex(
            dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256)));
          if doom_teavm_sim_frame_length(0)<>c_frame_bytes then
            raise_application_error(-20796,'normal reference frame length');
          end if;
          append_normal(l_normal);
          l_normal_sha:=lower(rawtohex(
            dbms_crypto.hash(l_normal,dbms_crypto.hash_sh256)));
          if l_row_major_sha<>l_normal_sha then
            raise_application_error(
              -20796,'live raster exactness mismatch at tic '||l_frontier);
          end if;
          l_exact:=l_exact+1;
          dbms_output.put_line(
            'PMLE_LIVE_COMMAND_EQUIVALENCE|PASS|window='||p_name||
            '|tic='||l_frontier||'|sha256='||l_normal_sha);
        end if;
      end if;
    end loop;
    l_expected_tic:=p_offset+c_warmup+c_samples;
    if l_frontier<>l_expected_tic or l_exact<>3 then
      raise_application_error(-20796,'live raster incomplete window');
    end if;
    if l_suspects>floor(c_samples*.005) then
      raise_application_error(-20796,'live raster clock exclusion cap');
    end if;
    sort_values(l_step);sort_values(l_render);sort_values(l_egress);
    sort_values(l_pipeline);sort_values(l_commands);
    dbms_output.put_line(
      'PMLE_LIVE_COMMAND_RANK|DIAGNOSTIC_NOT_GATE|window='||p_name||
      '|offset='||p_offset||'|samples='||c_samples||
      '|warmup='||c_warmup||'|frame_bytes='||c_frame_bytes||
      '|unique='||l_unique||'|exact_samples='||l_exact||
      '|asset_resets='||doom_teavm_live_asset_resets||
      '|command_min='||l_command_min||'|command_p50='||
        l_commands(ceil(c_samples*.5))||'|command_p95='||
        l_commands(ceil(c_samples*.95))||'|command_max='||l_command_max||
      '|step_p50_ms='||
        to_char(l_step(ceil(c_samples*.5)),'FM9999990.000')||
      '|step_p95_ms='||
        to_char(l_step(ceil(c_samples*.95)),'FM9999990.000')||
      '|render_p50_ms='||
        to_char(l_render(ceil(c_samples*.5)),'FM9999990.000')||
      '|render_p95_ms='||
        to_char(l_render(ceil(c_samples*.95)),'FM9999990.000')||
      '|egress_p50_ms='||
        to_char(l_egress(ceil(c_samples*.5)),'FM9999990.000')||
      '|egress_p95_ms='||
        to_char(l_egress(ceil(c_samples*.95)),'FM9999990.000')||
      '|pipeline_p50_ms='||
        to_char(l_pipeline(ceil(c_samples*.5)),'FM9999990.000')||
      '|pipeline_p95_ms='||
        to_char(l_pipeline(ceil(c_samples*.95)),'FM9999990.000')||
      '|throughput_fps='||
        to_char(c_samples*1000/sum_pipeline,'FM9999990.000')||
      '|clock_suspects='||l_suspects||
      '|exact_30fps='||
        case when l_pipeline(ceil(c_samples*.95))<=33.333
          then 'PASS' else 'FAIL' end);
  end;

  function sum_pipeline return number is
    l_total number:=0;
  begin
    for index_ in 1..c_samples loop
      l_total:=l_total+l_pipeline(index_);
    end loop;
    return l_total;
  end;
begin
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  dbms_lob.createtemporary(l_normal,true,dbms_lob.call);
  run_window('PEAK_AWAKE',100);
  run_window('QUIET_ROUTE',1200);
  doom_teavm_sim_release;
  dbms_lob.freetemporary(l_frame);
  dbms_lob.freetemporary(l_normal);
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
