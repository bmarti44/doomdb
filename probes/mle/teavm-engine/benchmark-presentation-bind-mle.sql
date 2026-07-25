whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off linesize 32767 trimspool on serveroutput on size unlimited

declare
  c_frame_bytes constant pls_integer:=320*200;
  l_warmup_count pls_integer:=10;
  l_sample_count pls_integer:=100;
  l_p50_index pls_integer;l_p95_index pls_integer;l_p99_index pls_integer;
  type sample_array is table of number index by pls_integer;
  type sha_array is table of varchar2(64) index by pls_integer;
  l_step sample_array;l_persist sample_array;l_pipeline sample_array;
  l_seen sha_array;
  l_wad blob;l_tables blob;l_frame blob;
  l_length pls_integer;l_offset pls_integer;l_loaded number;l_frontier number;
  l_sink_frame_id number;l_persisted number;
  l_chunk raw(32767);l_commands raw(32);
  l_status varchar2(32767);
  l_started timestamp with time zone;
  l_pipeline_started timestamp with time zone;
  l_frame_sha raw(32);
  l_classification varchar2(32):='DIAGNOSTIC_NOT_GATE';
  l_transport varchar2(40):='direct_uint8array_blob_insert';
  l_direct_mode varchar2(32):='UNSUPPORTED';
  l_use_locator boolean:=false;
  l_chain raw(32):=hextoraw(rpad('00',64,'0'));
  l_unique pls_integer:=0;l_step_temporary number;l_persist_temporary number;
  l_pipeline_temporary number;
  l_temporary_lobs_before number:=0;l_temporary_lobs_after number:=0;

  function elapsed_ms(p_started timestamp with time zone) return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin
    return extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000;
  end;

  procedure sort_samples(
      p_values in out nocopy sample_array,p_count pls_integer) is
    l_swap number;
  begin
    for left_ in 1..p_count-1 loop
      for right_ in left_+1..p_count loop
        if p_values(right_)<p_values(left_) then
          l_swap:=p_values(left_);
          p_values(left_):=p_values(right_);
          p_values(right_):=l_swap;
        end if;
      end loop;
    end loop;
  end;
begin
  if sys_context('userenv','client_identifier')=
      'PMLE_FRAME_BIND_DIRECT_GATE_300' then
    l_warmup_count:=30;
    l_sample_count:=300;
    l_classification:='ACCEPTANCE_GATE';
  elsif sys_context('userenv','client_identifier')=
      'PMLE_FRAME_BIND_LOCATOR_DIAGNOSTIC' then
    l_transport:='persistent_returning_oracle_blob';
    l_use_locator:=true;
  elsif sys_context('userenv','client_identifier')=
      'PMLE_FRAME_BIND_LOCATOR_GATE_300' then
    l_warmup_count:=30;
    l_sample_count:=300;
    l_classification:='ACCEPTANCE_GATE';
    l_transport:='persistent_returning_oracle_blob';
    l_use_locator:=true;
  elsif sys_context('userenv','client_identifier') is not null then
    raise_application_error(
      -20796,'unsupported presentation bind profile: '||
      sys_context('userenv','client_identifier'));
  end if;
  l_p50_index:=ceil(l_sample_count*0.50);
  l_p95_index:=ceil(l_sample_count*0.95);
  l_p99_index:=ceil(l_sample_count*0.99);
  if not l_use_locator then
    l_direct_mode:=doom_teavm_bind_direct_mode;
  end if;
  doom_teavm_bind_release;
  select payload_bytes into l_wad from doom_engine_artifact
   where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_loaded:=doom_teavm_bind_allocate(l_length);
  l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_bind_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_tables from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_tables);
  l_loaded:=doom_teavm_bind_table_allocate(l_length);
  l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(
      l_tables,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_bind_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_status:=doom_teavm_bind_multi_init_game(2,0,3,1,1);
  l_wad:=null;
  l_tables:=null;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temporary_lobs_before
    from v$temporary_lobs
   where sid=to_number(sys_context('USERENV','SID'));

  l_commands:=hextoraw(
    '1900000000000000'||
    '1200000000000000'||
    '0000000000000000'||
    '0000000000000000');

  for sample_ in 1..l_warmup_count+l_sample_count loop
    l_pipeline_started:=systimestamp;
    l_frontier:=doom_teavm_bind_authority_step(2,3,l_commands);
    l_step_temporary:=elapsed_ms(l_pipeline_started);
    l_started:=systimestamp;
    if l_use_locator then
      l_persisted:=doom_teavm_bind_persist_locator(0,sample_);
    else
      l_persisted:=doom_teavm_bind_persist_direct(0,sample_);
    end if;
    l_persist_temporary:=elapsed_ms(l_started);
    -- Prove a durable frame and exercise the persistent-row locator across a
    -- real transaction boundary on every sample.
    commit;
    l_pipeline_temporary:=elapsed_ms(l_pipeline_started);
    if l_persisted<>c_frame_bytes then
      raise_application_error(
        -20796,'persisted presentation frame length mismatch: '||l_persisted);
    end if;

    -- Hashing is deliberately outside pipeline timing. The persisted BLOB,
    -- however, must already be exact when renderPlayerFramePersist returns.
    select frame_id,payload into l_sink_frame_id,l_frame
      from doom_teavm_frame_sink
     where sink_id=(
       select max(sink_id) from doom_teavm_frame_sink
        where frame_id=sample_);
    if l_sink_frame_id<>sample_ or dbms_lob.getlength(l_frame)<>c_frame_bytes then
      raise_application_error(
        -20796,'presentation frame sink mismatch at sample '||sample_);
    end if;

    if sample_>l_warmup_count then
      l_step(sample_-l_warmup_count):=l_step_temporary;
      l_persist(sample_-l_warmup_count):=l_persist_temporary;
      l_pipeline(sample_-l_warmup_count):=l_pipeline_temporary;
      l_frame_sha:=dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256);
      l_chain:=dbms_crypto.hash(
        utl_raw.concat(l_chain,l_frame_sha),dbms_crypto.hash_sh256);
      if sample_>l_warmup_count+1 then
        for prior_ in 1..sample_-l_warmup_count-1 loop
          if l_seen(prior_)=lower(rawtohex(l_frame_sha)) then
            raise_application_error(
              -20796,'presentation bind frame was not unique at sample '||
              (sample_-l_warmup_count));
          end if;
        end loop;
      end if;
      l_seen(sample_-l_warmup_count):=lower(rawtohex(l_frame_sha));
      l_unique:=l_unique+1;
    end if;
    -- Do not retain even a read-only verification locator into the next
    -- frame transaction.
    l_frame:=null;
  end loop;

  sort_samples(l_step,l_sample_count);
  sort_samples(l_persist,l_sample_count);
  sort_samples(l_pipeline,l_sample_count);
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temporary_lobs_after
    from v$temporary_lobs
   where sid=to_number(sys_context('USERENV','SID'));
  dbms_output.put_line(
    'PMLE_PRESENTATION_BIND_RANK|'||l_classification||
    '|transport='||l_transport||
    '|direct_mode='||l_direct_mode||
    '|commit_per_frame=YES'||
    '|samples='||l_sample_count||'|warmup='||l_warmup_count||
    '|frame_bytes='||c_frame_bytes||'|unique='||l_unique||
    '|step_p50_ms='||to_char(l_step(l_p50_index),'FM9999990.000')||
    '|step_p95_ms='||to_char(l_step(l_p95_index),'FM9999990.000')||
    '|persist_p50_ms='||to_char(l_persist(l_p50_index),'FM9999990.000')||
    '|persist_p95_ms='||to_char(l_persist(l_p95_index),'FM9999990.000')||
    '|persist_p99_ms='||to_char(l_persist(l_p99_index),'FM9999990.000')||
    '|pipeline_p50_ms='||to_char(l_pipeline(l_p50_index),'FM9999990.000')||
    '|pipeline_p95_ms='||to_char(l_pipeline(l_p95_index),'FM9999990.000')||
    '|pipeline_p99_ms='||to_char(l_pipeline(l_p99_index),'FM9999990.000')||
    '|temporary_lobs_before='||l_temporary_lobs_before||
    '|temporary_lobs_after='||l_temporary_lobs_after||
    '|temporary_lobs_delta='||
      (l_temporary_lobs_after-l_temporary_lobs_before)||
    '|exact_30fps='||
      case when l_pipeline(l_p95_index)<=33.333 then 'PASS' else 'FAIL' end||
      '|chain_sha256='||lower(rawtohex(l_chain))||
      '|frontier='||l_frontier);
  doom_teavm_bind_release;
  delete from doom_teavm_frame_sink where sink_id<>1;
  update doom_teavm_frame_sink
     set frame_id=-1,payload=empty_blob()
   where sink_id=1;
  commit;
exception when others then
  begin doom_teavm_bind_release;exception when others then null;end;
  rollback;
  begin
    delete from doom_teavm_frame_sink where sink_id<>1;
    update doom_teavm_frame_sink
       set frame_id=-1,payload=empty_blob()
     where sink_id=1;
    commit;
  exception when others then
    rollback;
  end;
  raise;
end;
/
rollback;
