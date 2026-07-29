whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off
set verify off
set feedback off
set heading off
set pagesize 0
set linesize 32767
set trimspool on
set serveroutput on size unlimited

declare
  c_offset constant pls_integer:=310;
  c_warmup constant pls_integer:=35;
  c_samples constant pls_integer:=350;
  c_frame_bytes constant pls_integer:=64000;
  type number_list is table of number index by binary_integer;
  l_pipeline number_list;l_persist number_list;
  l_wad blob;l_tables blob;l_payload blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_frontier number:=0;l_result number;l_batch_size pls_integer:=1;
  l_groups pls_integer;l_group pls_integer:=0;l_in_group pls_integer:=0;
  l_raw boolean:=false;l_profile varchar2(32);
  l_wall_start timestamp with time zone;l_persist_start timestamp with time zone;
  l_get_start number;l_total_wall number;l_total_get number;
  l_temp_before number;l_temp_after number;l_clock_suspects number:=0;
  l_sink_length number;l_sink_count number;l_sink_codec varchar2(32);
  l_sink_first number;l_sink_last number;

  function elapsed_ms(p_start timestamp with time zone) return number is
    d interval day to second:=systimestamp-p_start;
  begin
    return extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
  end;
  procedure quicksort(
      p_values in out nocopy number_list,p_left binary_integer,
      p_right binary_integer) is
    i binary_integer:=p_left;j binary_integer:=p_right;
    pivot number:=p_values(trunc((p_left+p_right)/2));swap number;
  begin
    while i<=j loop
      while p_values(i)<pivot loop i:=i+1;end loop;
      while p_values(j)>pivot loop j:=j-1;end loop;
      if i<=j then
        swap:=p_values(i);p_values(i):=p_values(j);p_values(j):=swap;
        i:=i+1;j:=j-1;
      end if;
    end loop;
    if p_left<j then quicksort(p_values,p_left,j);end if;
    if i<p_right then quicksort(p_values,i,p_right);end if;
  end;
  procedure load_asset(p_blob blob,p_kind varchar2) is
  begin
    l_length:=dbms_lob.getlength(p_blob);l_offset:=0;
    if p_kind='IWAD' then l_loaded:=doom_dvr_bind_allocate(l_length);
    else l_loaded:=doom_dvr_bind_table_allocate(l_length);end if;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(32767,l_length-l_offset),l_offset+1);
      if p_kind='IWAD' then
        l_loaded:=doom_dvr_bind_load(l_offset,l_chunk);
      else
        l_loaded:=doom_dvr_bind_table_load(l_offset,l_chunk);
      end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;
begin
  l_profile:=sys_context('userenv','client_identifier');
  case l_profile
    when 'OCI_DVR_BOUNDARY_RAW_1' then l_raw:=true;l_batch_size:=1;
    when 'OCI_DVR_BOUNDARY_DFR1_1' then l_batch_size:=1;
    when 'OCI_DVR_BOUNDARY_DFR1_5' then l_batch_size:=5;
    when 'OCI_DVR_BOUNDARY_DFR1_10' then l_batch_size:=10;
    when 'OCI_DVR_BOUNDARY_DFR1_35' then l_batch_size:=35;
    else raise_application_error(-20796,'unsupported OCI DVR boundary profile');
  end case;
  if mod(c_samples,l_batch_size)<>0 then
    raise_application_error(-20796,'DVR boundary sample count is not divisible');
  end if;
  l_groups:=c_samples/l_batch_size;
  doom_dvr_bind_release;
  update doom_dvr_frame_sink set batch_id=-1,frame_count=0,
    first_frame_id=-1,last_frame_id=-1,payload=empty_blob();
  commit;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob into l_tables from doom_teavm_sim_source;
  load_asset(l_wad,'IWAD');load_asset(l_tables,'TABLES');
  if doom_dvr_bind_init(2,1,3,1,1)
      not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'DVR boundary init mismatch');
  end if;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_before from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));

  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector from doom_mle_perf_vector
    where stream_name='live-dm-2026-07-23'
      and tic between 1 and c_offset+c_warmup+c_samples order by tic
  ) loop
    if command_.tic>c_offset+c_warmup and l_in_group=0 then
      l_wall_start:=systimestamp;l_get_start:=dbms_utility.get_time;
      if not l_raw then l_result:=doom_dvr_bind_reset_batch;end if;
    end if;
    l_frontier:=doom_dvr_bind_step(
      2,command_.membership,command_.command_vector);
    if command_.tic<=c_offset then continue;end if;
    if command_.tic<=c_offset+c_warmup then
      if l_raw then
        l_result:=doom_dvr_bind_render(0);
      else
        l_result:=doom_dvr_bind_append(0,l_frontier);
      end if;
      if command_.tic=c_offset+c_warmup then
        if l_raw then
          l_result:=doom_dvr_bind_persist_raw(l_frontier);
        else
          l_result:=doom_dvr_bind_persist_batch(-l_frontier+1000000);
          l_result:=doom_dvr_bind_reset_batch;
        end if;
        commit;
      end if;
      continue;
    end if;

    if l_raw then
      l_result:=doom_dvr_bind_render(0);
    else
      l_result:=doom_dvr_bind_append(0,l_frontier);
    end if;
    l_in_group:=l_in_group+1;
    if l_in_group=l_batch_size then
      l_persist_start:=systimestamp;
      if l_raw then
        l_result:=doom_dvr_bind_persist_raw(l_frontier);
      else
        l_result:=doom_dvr_bind_persist_batch(l_frontier);
      end if;
      l_group:=l_group+1;
      l_persist(l_group):=elapsed_ms(l_persist_start)/l_batch_size;
      commit;
      l_pipeline(l_group):=elapsed_ms(l_wall_start)/l_batch_size;
      l_total_get:=(dbms_utility.get_time-l_get_start)*10/l_batch_size;
      if abs(l_pipeline(l_group)-l_total_get)>30 then
        l_clock_suspects:=l_clock_suspects+1;
      end if;
      select payload,dbms_lob.getlength(payload),frame_count,codec_id,
        first_frame_id,last_frame_id
        into l_payload,l_sink_length,l_sink_count,l_sink_codec,
          l_sink_first,l_sink_last
        from doom_dvr_frame_sink where sink_id=case when l_raw then 1 else 2 end;
      if l_sink_length<>l_result or
          l_sink_count<>l_batch_size or
          l_sink_last<>l_frontier or
          l_sink_first<>l_frontier-l_batch_size+1 or
          (l_raw and l_sink_codec<>'RAW_INDEXED_V1') or
          (not l_raw and l_sink_codec<>'DOOM_DFR1_RLE') then
        raise_application_error(-20796,'DVR boundary sink mismatch');
      end if;
      if not l_raw and (
          dbms_lob.substr(l_payload,4,1)<>hextoraw('44464231') or
          to_number(rawtohex(dbms_lob.substr(l_payload,1,5)),'XX')
            <>l_batch_size) then
        raise_application_error(-20796,'DVR DFB1 batch framing mismatch');
      end if;
      l_payload:=null;l_in_group:=0;
    end if;
  end loop;
  if l_group<>l_groups or l_frontier<>c_offset+c_warmup+c_samples then
    raise_application_error(-20796,'DVR boundary coverage mismatch');
  end if;
  quicksort(l_pipeline,1,l_groups);quicksort(l_persist,1,l_groups);
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_after from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  l_total_wall:=l_pipeline(ceil(l_groups*.95));
  dbms_output.put_line(
    'PMLE_OCI_DVR_BOUNDARY|PASS|classification=POST_RELEASE_DVR_GATE'||
    '|profile='||l_profile||'|codec='||
      case when l_raw then 'RAW_INDEXED_V1' else 'DOOM_DFR1_RLE' end||
    '|batch_size='||l_batch_size||'|frames='||c_samples||
    '|groups='||l_groups||
    '|persist_amortized_p50_ms='||
      to_char(l_persist(ceil(l_groups*.5)),'FM9999990.000')||
    '|persist_amortized_p95_ms='||
      to_char(l_persist(ceil(l_groups*.95)),'FM9999990.000')||
    '|pipeline_amortized_p50_ms='||
      to_char(l_pipeline(ceil(l_groups*.5)),'FM9999990.000')||
    '|pipeline_amortized_p95_ms='||
      to_char(l_pipeline(ceil(l_groups*.95)),'FM9999990.000')||
    '|sustained_fps_p95='||
      to_char(1000/l_pipeline(ceil(l_groups*.95)),'FM999990.000')||
    '|clock_suspects='||l_clock_suspects||
    '|clock_exclusion_cap='||floor(l_groups*.005)||
    '|temporary_lobs_before='||l_temp_before||
    '|temporary_lobs_after='||l_temp_after||
    '|temporary_lobs_delta='||(l_temp_after-l_temp_before)||
    '|backlog=0|boundary_gate='||
      case when l_total_wall<=28.571
        and l_clock_suspects<=floor(l_groups*.005)
        and l_temp_after=l_temp_before
      then 'PASS' else 'FAIL' end);
  doom_dvr_bind_release;
  commit;
exception when others then
  begin doom_dvr_bind_release;exception when others then null;end;
  rollback;raise;
end;
/
