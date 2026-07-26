whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimspool on serveroutput on size unlimited

begin execute immediate 'drop table doom_mle_raw_frame_ring purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
create table doom_mle_raw_frame_ring(
  ring_slot number primary key,
  frame_tic number,
  payload_0 raw(32767),
  payload_1 raw(31233),
  constraint doom_mle_raw_frame_ring_slot_ck
    check(ring_slot between 0 and 63)
);
begin
  for slot_ in 0..63 loop
    insert into doom_mle_raw_frame_ring(ring_slot,frame_tic)
    values(slot_,-1);
  end loop;
  commit;
end;
/

declare
  c_offset constant pls_integer:=310;
  c_warmup constant pls_integer:=30;
  c_samples constant pls_integer:=300;
  c_frame_bytes constant pls_integer:=64000;
  c_expected_chain constant varchar2(64):=
    '4e6159b218afc6ec15a763026acaea83038d8bb0764c097069094fe988578a6a';
  type numbers is table of number index by binary_integer;
  type hashes is table of varchar2(64) index by binary_integer;
  l_step numbers;l_render numbers;l_egress numbers;l_publish numbers;
  l_pipeline numbers;l_seen hashes;
  l_wad blob;l_tables blob;l_temp blob;l_chunk raw(32767);
  l_raw0 raw(32767);l_raw1 raw(31233);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_frontier number:=0;l_frame_length number;l_index pls_integer;
  l_start timestamp with time zone;l_stage timestamp with time zone;
  l_tick_start number;l_tick_elapsed number;l_wall_elapsed number;
  l_step_ms number;l_render_ms number;l_egress_ms number;l_publish_ms number;
  l_suspects number:=0;l_temp_before number;l_temp_after number;
  l_frame_sha raw(32);l_chain raw(32):=hextoraw(rpad('0',64,'0'));

  function elapsed_ms(p_start timestamp with time zone) return number is
    d interval day to second:=systimestamp-p_start;
  begin
    return extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
  end;
  procedure quicksort(
      p_values in out nocopy numbers,p_left binary_integer,
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
  if sys_context('userenv','client_identifier')<>'OCI_RAW_FRAME_RING_300' then
    raise_application_error(-20796,'unsupported raw-frame ring profile');
  end if;
  doom_teavm_bind_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob into l_tables from doom_teavm_sim_source;
  load_asset(l_wad,'IWAD');load_asset(l_tables,'TABLES');
  if doom_teavm_bind_multi_init_game(2,1,3,1,1)
      not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'raw-frame ring init mismatch');
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
    if command_.tic<=c_offset then
      l_frontier:=doom_teavm_bind_authority_step(
        2,command_.membership,command_.command_vector);
      continue;
    end if;
    l_start:=systimestamp;l_tick_start:=dbms_utility.get_time;
    l_frontier:=doom_teavm_bind_authority_step(
      2,command_.membership,command_.command_vector);
    l_step_ms:=elapsed_ms(l_start);
    l_stage:=systimestamp;
    l_frame_length:=doom_teavm_bind_frame_length(0);
    l_render_ms:=elapsed_ms(l_stage);
    if l_frame_length<>c_frame_bytes then
      raise_application_error(-20796,'raw-frame length mismatch');
    end if;
    l_stage:=systimestamp;
    l_raw0:=doom_teavm_bind_frame_chunk(0,32767);
    l_raw1:=doom_teavm_bind_frame_chunk(32767,31233);
    l_egress_ms:=elapsed_ms(l_stage);
    if utl_raw.length(l_raw0)<>32767 or utl_raw.length(l_raw1)<>31233 then
      raise_application_error(-20796,'raw-frame chunk mismatch');
    end if;
    l_stage:=systimestamp;
    update doom_mle_raw_frame_ring
      set frame_tic=l_frontier,payload_0=l_raw0,payload_1=l_raw1
      where ring_slot=mod(l_frontier,64);
    if sql%rowcount<>1 then
      raise_application_error(-20796,'raw-frame ring publish mismatch');
    end if;
    commit write batch nowait;
    l_publish_ms:=elapsed_ms(l_stage);
    l_wall_elapsed:=elapsed_ms(l_start);
    l_tick_elapsed:=(dbms_utility.get_time-l_tick_start)*10;
    if abs(l_wall_elapsed-l_tick_elapsed)>30 then
      l_suspects:=l_suspects+1;
    end if;
    if command_.tic>c_offset+c_warmup then
      l_index:=command_.tic-c_offset-c_warmup;
      dbms_lob.createtemporary(l_temp,true,dbms_lob.call);
      dbms_lob.writeappend(l_temp,32767,l_raw0);
      dbms_lob.writeappend(l_temp,31233,l_raw1);
      l_frame_sha:=dbms_crypto.hash(l_temp,dbms_crypto.hash_sh256);
      dbms_lob.freetemporary(l_temp);l_temp:=null;
      for prior_ in 1..l_index-1 loop
        if l_seen(prior_)=lower(rawtohex(l_frame_sha)) then
          raise_application_error(-20796,'raw-frame ring duplicate');
        end if;
      end loop;
      l_seen(l_index):=lower(rawtohex(l_frame_sha));
      l_chain:=dbms_crypto.hash(
        utl_raw.concat(l_chain,l_frame_sha),dbms_crypto.hash_sh256);
      l_step(l_index):=l_step_ms;
      l_render(l_index):=l_render_ms;
      l_egress(l_index):=l_egress_ms;
      l_publish(l_index):=l_publish_ms;
      l_pipeline(l_index):=l_wall_elapsed;
    end if;
  end loop;
  if lower(rawtohex(l_chain))<>c_expected_chain then
    raise_application_error(-20796,'raw-frame ring Node chain mismatch');
  end if;
  quicksort(l_step,1,c_samples);quicksort(l_render,1,c_samples);
  quicksort(l_egress,1,c_samples);quicksort(l_publish,1,c_samples);
  quicksort(l_pipeline,1,c_samples);
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_after from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  dbms_output.put_line(
    'PMLE_OCI_RAW_FRAME_RING|DIAGNOSTIC_NOT_GATE|frames='||c_samples||
    '|unique='||c_samples||'|frame_bytes='||c_frame_bytes||
    '|ring_slots=64|transport=two_raw_columns'||
    '|commit=WRITE_BATCH_NOWAIT'||
    '|step_p95_ms='||to_char(l_step(ceil(c_samples*.95)),'FM9999990.000')||
    '|render_p95_ms='||
      to_char(l_render(ceil(c_samples*.95)),'FM9999990.000')||
    '|egress_p95_ms='||
      to_char(l_egress(ceil(c_samples*.95)),'FM9999990.000')||
    '|publish_p95_ms='||
      to_char(l_publish(ceil(c_samples*.95)),'FM9999990.000')||
    '|pipeline_p50_ms='||
      to_char(l_pipeline(ceil(c_samples*.5)),'FM9999990.000')||
    '|pipeline_p95_ms='||
      to_char(l_pipeline(ceil(c_samples*.95)),'FM9999990.000')||
    '|pipeline_fps_p95='||
      to_char(1000/l_pipeline(ceil(c_samples*.95)),'FM999990.000')||
    '|clock_suspects='||l_suspects||
    '|clock_exclusion_cap='||floor(c_samples*.005)||
    '|temporary_lobs_before='||l_temp_before||
    '|temporary_lobs_after='||l_temp_after||
    '|temporary_lobs_delta='||(l_temp_after-l_temp_before)||
    '|chain_sha256='||lower(rawtohex(l_chain))||
    '|raw_30fps='||case
      when l_pipeline(ceil(c_samples*.95))<=33.333
       and l_suspects<=floor(c_samples*.005)
       and l_temp_after=l_temp_before
      then 'PASS' else 'FAIL' end);
  doom_teavm_bind_release;
  commit;
exception when others then
  if dbms_lob.istemporary(l_temp)=1 then dbms_lob.freetemporary(l_temp);end if;
  begin doom_teavm_bind_release;exception when others then null;end;
  rollback;raise;
end;
/
