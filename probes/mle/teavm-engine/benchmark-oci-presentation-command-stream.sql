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
  c_frame_bytes constant pls_integer:=64000;
  l_samples pls_integer:=100;l_warmup pls_integer:=10;
  l_transport varchar2(40):='direct_uint8array_blob_insert';
  l_expected_chain varchar2(64):=
    '44852aabf9f3da7ed1e0adf4d8f3e711798de8cd9a9f43aa7e60eb3f95421acd';
  l_locator boolean:=false;
  type numbers is table of number index by pls_integer;
  type hashes is table of varchar2(64) index by pls_integer;
  l_step numbers;l_persist numbers;l_pipeline numbers;l_seen hashes;
  l_wad blob;l_tables blob;l_frame blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;l_frontier number:=0;
  l_persisted number;l_sink_frame number;
  l_wall_start timestamp with time zone;l_stage_start timestamp with time zone;
  l_tick_start number;l_wall_ms number;l_tick_ms number;
  l_step_ms number;l_persist_ms number;l_suspects number:=0;
  l_frame_sha raw(32);l_chain raw(32):=hextoraw(rpad('0',64,'0'));
  l_temp_before number:=0;l_temp_after number:=0;
  l_artifact_sha varchar2(64);

  function elapsed_ms(p_start timestamp with time zone) return number is
    d interval day to second:=systimestamp-p_start;
  begin
    return extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
  end;
  procedure sort_values(v in out nocopy numbers,n pls_integer) is swap number;
  begin
    for i in 1..n-1 loop for j in i+1..n loop
      if v(j)<v(i) then swap:=v(i);v(i):=v(j);v(j):=swap;end if;
    end loop;end loop;
  end;
  procedure load_asset(b blob,kind varchar2) is
  begin
    l_length:=dbms_lob.getlength(b);l_offset:=0;
    if kind='IWAD' then l_loaded:=doom_teavm_bind_allocate(l_length);
    else l_loaded:=doom_teavm_bind_table_allocate(l_length);end if;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(b,least(32767,l_length-l_offset),l_offset+1);
      if kind='IWAD' then l_loaded:=doom_teavm_bind_load(l_offset,l_chunk);
      else l_loaded:=doom_teavm_bind_table_load(l_offset,l_chunk);end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;
begin
  if sys_context('userenv','client_identifier')=
      'OCI_PRESENTATION_DIRECT_300' then
    l_samples:=300;l_warmup:=30;
    l_expected_chain:=
      '4e6159b218afc6ec15a763026acaea83038d8bb0764c097069094fe988578a6a';
  elsif sys_context('userenv','client_identifier')=
      'OCI_PRESENTATION_LOCATOR_100' then
    l_locator:=true;l_transport:='persistent_returning_oracle_blob';
  elsif sys_context('userenv','client_identifier')=
      'OCI_PRESENTATION_LOCATOR_300' then
    l_samples:=300;l_warmup:=30;l_locator:=true;
    l_transport:='persistent_returning_oracle_blob';
    l_expected_chain:=
      '4e6159b218afc6ec15a763026acaea83038d8bb0764c097069094fe988578a6a';
  elsif sys_context('userenv','client_identifier')<>
      'OCI_PRESENTATION_DIRECT_100' then
    raise_application_error(-20796,'unsupported OCI presentation profile');
  end if;
  delete from doom_teavm_frame_sink where sink_id<>1;
  update doom_teavm_frame_sink set frame_id=-1,payload=empty_blob()
    where sink_id=1;
  commit;
  doom_teavm_bind_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob,
    lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))
    into l_tables,l_artifact_sha from doom_teavm_sim_source;
  load_asset(l_wad,'IWAD');load_asset(l_tables,'TABLES');
  if doom_teavm_bind_multi_init_game(2,1,3,1,1)
      not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'presentation init mismatch');
  end if;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_before from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));

  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector from doom_mle_perf_vector
    where stream_name='live-dm-2026-07-23'
      and tic between 1 and c_offset+l_warmup+l_samples order by tic
  ) loop
    if command_.tic<>l_frontier+1 then
      raise_application_error(-20796,'presentation stream gap');
    end if;
    if command_.tic<=c_offset then
      l_frontier:=doom_teavm_bind_authority_step(
        2,command_.membership,command_.command_vector);
      continue;
    end if;
    l_wall_start:=systimestamp;l_tick_start:=dbms_utility.get_time;
    l_frontier:=doom_teavm_bind_authority_step(
      2,command_.membership,command_.command_vector);
    l_step_ms:=elapsed_ms(l_wall_start);l_stage_start:=systimestamp;
    if l_locator then
      l_persisted:=doom_teavm_bind_persist_locator(0,l_frontier);
    else
      l_persisted:=doom_teavm_bind_persist_direct(0,l_frontier);
    end if;
    l_persist_ms:=elapsed_ms(l_stage_start);
    commit;
    l_wall_ms:=elapsed_ms(l_wall_start);
    l_tick_ms:=(dbms_utility.get_time-l_tick_start)*10;
    if abs(l_wall_ms-l_tick_ms)>30 then l_suspects:=l_suspects+1;end if;
    if l_persisted<>c_frame_bytes then
      raise_application_error(-20796,'presentation BLOB length mismatch');
    end if;
    select frame_id,payload into l_sink_frame,l_frame
      from doom_teavm_frame_sink where frame_id=l_frontier;
    if l_sink_frame<>l_frontier or
        dbms_lob.getlength(l_frame)<>c_frame_bytes then
      raise_application_error(-20796,'presentation sink mismatch');
    end if;
    if l_frontier>c_offset+l_warmup then
      l_step(l_frontier-c_offset-l_warmup):=l_step_ms;
      l_persist(l_frontier-c_offset-l_warmup):=l_persist_ms;
      l_pipeline(l_frontier-c_offset-l_warmup):=l_wall_ms;
      l_frame_sha:=dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256);
      for prior_ in 1..l_frontier-c_offset-l_warmup-1 loop
        if l_seen(prior_)=lower(rawtohex(l_frame_sha)) then
          raise_application_error(-20796,'non-unique presentation frame');
        end if;
      end loop;
      l_seen(l_frontier-c_offset-l_warmup):=lower(rawtohex(l_frame_sha));
      l_chain:=dbms_crypto.hash(utl_raw.concat(l_chain,l_frame_sha),
        dbms_crypto.hash_sh256);
    end if;
    l_frame:=null;
  end loop;
  if lower(rawtohex(l_chain))<>l_expected_chain then
    raise_application_error(-20796,'presentation Node chain mismatch');
  end if;
  if l_suspects>floor(l_samples*.005) then
    raise_application_error(-20796,'presentation clock exclusion cap');
  end if;
  sort_values(l_step,l_samples);sort_values(l_persist,l_samples);
  sort_values(l_pipeline,l_samples);
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_after from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  dbms_output.put_line(
    'PMLE_OCI_PRESENTATION_RANK|DIAGNOSTIC_NOT_GATE'||
    '|transport='||l_transport||'|samples='||l_samples||
    '|warmup='||l_warmup||'|stream_offset='||c_offset||
    '|frontier='||l_frontier||'|frame_bytes='||c_frame_bytes||
    '|unique='||l_samples||
    '|step_p50_ms='||to_char(l_step(ceil(l_samples*.5)),'FM9999990.000')||
    '|step_p95_ms='||to_char(l_step(ceil(l_samples*.95)),'FM9999990.000')||
    '|persist_p50_ms='||
      to_char(l_persist(ceil(l_samples*.5)),'FM9999990.000')||
    '|persist_p95_ms='||
      to_char(l_persist(ceil(l_samples*.95)),'FM9999990.000')||
    '|persist_p99_ms='||
      to_char(l_persist(ceil(l_samples*.99)),'FM9999990.000')||
    '|pipeline_p50_ms='||
      to_char(l_pipeline(ceil(l_samples*.5)),'FM9999990.000')||
    '|pipeline_p95_ms='||
      to_char(l_pipeline(ceil(l_samples*.95)),'FM9999990.000')||
    '|pipeline_p99_ms='||
      to_char(l_pipeline(ceil(l_samples*.99)),'FM9999990.000')||
    '|clock_suspects='||l_suspects||
    '|clock_exclusion_cap='||floor(l_samples*.005)||
    '|temporary_lobs_before='||l_temp_before||
    '|temporary_lobs_after='||l_temp_after||
    '|temporary_lobs_delta='||(l_temp_after-l_temp_before)||
    '|exact_30fps='||
      case when l_pipeline(ceil(l_samples*.95))<=33.333
        then 'PASS' else 'FAIL' end||
    '|artifact_sha256='||l_artifact_sha||
    '|stream_sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085'||
    '|chain_sha256='||lower(rawtohex(l_chain)));
  doom_teavm_bind_release;
  delete from doom_teavm_frame_sink where sink_id<>1;
  update doom_teavm_frame_sink set frame_id=-1,payload=empty_blob()
    where sink_id=1;
  commit;
exception when others then
  begin doom_teavm_bind_release;exception when others then null;end;
  rollback;raise;
end;
/
