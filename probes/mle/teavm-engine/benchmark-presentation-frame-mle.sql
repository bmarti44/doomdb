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
  l_step sample_array;l_render sample_array;l_egress sample_array;
  l_total sample_array;l_pipeline sample_array;
  l_seen sha_array;
  l_wad blob;l_tables blob;l_frame blob;
  l_length pls_integer;l_offset pls_integer;l_loaded number;l_frontier number;
  l_chunk raw(32767);l_commands raw(32);
  l_status varchar2(32767);
  l_started timestamp with time zone;
  l_total_started timestamp with time zone;
  l_pipeline_started timestamp with time zone;
  l_frame_sha raw(32);
  l_classification varchar2(32):='DIAGNOSTIC_NOT_GATE';
  l_chain raw(32):=hextoraw(rpad('00',64,'0'));
  l_unique pls_integer:=0;l_step_temporary number;l_render_temporary number;

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
  if sys_context('userenv','client_identifier')='PMLE_FRAME_GATE_300' then
    l_warmup_count:=30;
    l_sample_count:=300;
    l_classification:='ACCEPTANCE_GATE';
  elsif sys_context('userenv','client_identifier') is not null then
    raise_application_error(
      -20796,'unsupported presentation frame profile: '||
      sys_context('userenv','client_identifier'));
  end if;
  l_p50_index:=ceil(l_sample_count*0.50);
  l_p95_index:=ceil(l_sample_count*0.95);
  l_p99_index:=ceil(l_sample_count*0.99);
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

  -- Two moving players make the frame corpus unique without client-side
  -- prediction or any renderer-only state mutation.
  l_commands:=hextoraw(
    '1900000000000000'||
    '1200000000000000'||
    '0000000000000000'||
    '0000000000000000');

  for sample_ in 1..l_warmup_count+l_sample_count loop
    l_pipeline_started:=systimestamp;
    l_frontier:=doom_teavm_bind_authority_step(2,3,l_commands);
    l_step_temporary:=elapsed_ms(l_pipeline_started);
    l_total_started:=systimestamp;
    l_started:=l_total_started;
    l_length:=doom_teavm_bind_frame_length(0);
    if l_length<>c_frame_bytes then
      raise_application_error(
        -20796,'presentation frame length mismatch: '||l_length);
    end if;
    l_render_temporary:=elapsed_ms(l_started);

    dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
    l_offset:=0;
    l_started:=systimestamp;
    while l_offset<l_length loop
      l_chunk:=doom_teavm_bind_frame_chunk(
        l_offset,least(32767,l_length-l_offset));
      if utl_raw.length(l_chunk)<>least(32767,l_length-l_offset) then
        raise_application_error(
          -20796,'presentation frame short chunk at '||l_offset);
      end if;
      dbms_lob.writeappend(l_frame,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;

    if sample_>l_warmup_count then
      l_step(sample_-l_warmup_count):=l_step_temporary;
      l_render(sample_-l_warmup_count):=l_render_temporary;
      l_egress(sample_-l_warmup_count):=elapsed_ms(l_started);
      l_total(sample_-l_warmup_count):=elapsed_ms(l_total_started);
      l_pipeline(sample_-l_warmup_count):=elapsed_ms(l_pipeline_started);
      l_frame_sha:=dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256);
      l_chain:=dbms_crypto.hash(
        utl_raw.concat(l_chain,l_frame_sha),dbms_crypto.hash_sh256);
      if sample_>l_warmup_count+1 then
        for prior_ in 1..sample_-l_warmup_count-1 loop
          if l_seen(prior_)=lower(rawtohex(l_frame_sha)) then
            raise_application_error(
              -20796,'presentation frame was not unique at sample '||
              (sample_-l_warmup_count));
          end if;
        end loop;
      end if;
      l_seen(sample_-l_warmup_count):=lower(rawtohex(l_frame_sha));
      l_unique:=l_unique+1;
    end if;
    dbms_lob.freetemporary(l_frame);
  end loop;

  sort_samples(l_step,l_sample_count);
  sort_samples(l_render,l_sample_count);
  sort_samples(l_egress,l_sample_count);
  sort_samples(l_total,l_sample_count);
  sort_samples(l_pipeline,l_sample_count);
  dbms_output.put_line(
    'PMLE_PRESENTATION_FRAME_RANK|'||l_classification||
    '|samples='||l_sample_count||'|warmup='||l_warmup_count||
    '|frame_bytes='||c_frame_bytes||'|unique='||l_unique||
    '|step_p50_ms='||to_char(l_step(l_p50_index),'FM9999990.000')||
    '|step_p95_ms='||to_char(l_step(l_p95_index),'FM9999990.000')||
    '|render_p50_ms='||to_char(l_render(l_p50_index),'FM9999990.000')||
    '|render_p95_ms='||to_char(l_render(l_p95_index),'FM9999990.000')||
    '|render_p99_ms='||to_char(l_render(l_p99_index),'FM9999990.000')||
    '|egress_p50_ms='||to_char(l_egress(l_p50_index),'FM9999990.000')||
    '|egress_p95_ms='||to_char(l_egress(l_p95_index),'FM9999990.000')||
    '|total_p50_ms='||to_char(l_total(l_p50_index),'FM9999990.000')||
    '|total_p95_ms='||to_char(l_total(l_p95_index),'FM9999990.000')||
    '|total_p99_ms='||to_char(l_total(l_p99_index),'FM9999990.000')||
    '|pipeline_p50_ms='||to_char(l_pipeline(l_p50_index),'FM9999990.000')||
    '|pipeline_p95_ms='||to_char(l_pipeline(l_p95_index),'FM9999990.000')||
    '|pipeline_p99_ms='||to_char(l_pipeline(l_p99_index),'FM9999990.000')||
    '|exact_30fps='||
      case when l_pipeline(l_p95_index)<=33.333 then 'PASS' else 'FAIL' end||
    '|chain_sha256='||lower(rawtohex(l_chain))||
    '|frontier='||l_frontier);
  doom_teavm_bind_release;
exception when others then
  begin
    if dbms_lob.istemporary(l_frame)=1 then
      dbms_lob.freetemporary(l_frame);
    end if;
  exception when others then null;
  end;
  begin doom_teavm_bind_release;exception when others then null;end;
  raise;
end;
/
