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
  c_tics constant pls_integer:=5250;
  c_frame_bytes constant pls_integer:=64000;
  c_frame_chain constant varchar2(64):=
    'dc0cfe6a9cc79f592e9b04409508c7db29866308d2a886d7f344d1b75294330c';
  c_compressed_chain constant varchar2(64):=
    '2dc3a49eaf8a749f95be0293c8150807268846a35cbe71951eb52ab1ebdb7d8f';
  type number_list is table of number index by binary_integer;
  l_whole number_list;l_peak number_list;l_quiet number_list;
  l_whole_bytes number_list;l_peak_bytes number_list;l_quiet_bytes number_list;
  l_peak_count pls_integer:=0;l_quiet_count pls_integer:=0;
  l_wad blob;l_tables blob;l_chunk raw(32767);
  l_temp blob;l_frame_sha raw(32);l_compressed_sha raw(32);
  l_frame_chain raw(32):=hextoraw(rpad('0',64,'0'));
  l_compressed_chain raw(32):=hextoraw(rpad('0',64,'0'));
  l_length pls_integer;l_offset pls_integer;l_piece pls_integer;
  l_loaded number;l_frontier number:=0;l_compressed_length number;
  l_wall_start timestamp with time zone;l_compress_start timestamp with time zone;
  l_get_start number;l_wall_ms number;l_get_ms number;l_temp_before number;
  l_temp_after number;l_roundtrip number;l_artifact_sha varchar2(64);
  l_codec_sha varchar2(64);l_suspects number:=0;

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

  function retained_sha(p_compressed boolean,p_length pls_integer)
      return raw is
    result raw(32);
  begin
    dbms_lob.createtemporary(l_temp,true,dbms_lob.call);
    l_offset:=0;
    while l_offset<p_length loop
      l_piece:=least(32767,p_length-l_offset);
      if p_compressed then
        l_chunk:=doom_dvr_bind_compressed_chunk(l_offset,l_piece);
      else
        l_chunk:=doom_dvr_bind_frame_chunk(l_offset,l_piece);
      end if;
      if utl_raw.length(l_chunk)<>l_piece then
        raise_application_error(-20796,'DVR retained chunk mismatch');
      end if;
      dbms_lob.writeappend(l_temp,l_piece,l_chunk);
      l_offset:=l_offset+l_piece;
    end loop;
    result:=dbms_crypto.hash(l_temp,dbms_crypto.hash_sh256);
    dbms_lob.freetemporary(l_temp);l_temp:=null;
    return result;
  exception when others then
    if dbms_lob.istemporary(l_temp)=1 then
      dbms_lob.freetemporary(l_temp);
    end if;
    l_temp:=null;raise;
  end;
begin
  if sys_context('userenv','client_identifier')<>'OCI_DVR_CODEC_5250' then
    raise_application_error(-20796,'unsupported OCI DVR codec profile');
  end if;
  doom_dvr_bind_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob,
    lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))
    into l_tables,l_artifact_sha from doom_teavm_sim_source;
  select lower(rawtohex(dbms_crypto.hash(
      source_blob,dbms_crypto.hash_sh256)))
    into l_codec_sha from doom_mle_dvr_codec_source;
  load_asset(l_wad,'IWAD');load_asset(l_tables,'TABLES');
  if doom_dvr_bind_init(2,1,3,1,1)
      not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'DVR codec init mismatch');
  end if;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_before from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  l_wall_start:=systimestamp;l_get_start:=dbms_utility.get_time;
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector from doom_mle_perf_vector
    where stream_name='live-dm-2026-07-23' order by tic
  ) loop
    if command_.tic<>l_frontier+1 then
      raise_application_error(-20796,'DVR codec command stream gap');
    end if;
    l_frontier:=doom_dvr_bind_step(
      2,command_.membership,command_.command_vector);
    if doom_dvr_bind_render(0)<>c_frame_bytes then
      raise_application_error(-20796,'DVR frame length mismatch');
    end if;
    l_compress_start:=systimestamp;
    l_compressed_length:=doom_dvr_bind_compress;
    l_whole(command_.tic):=elapsed_ms(l_compress_start);
    l_whole_bytes(command_.tic):=l_compressed_length;
    if command_.tic between 101 and 800 then
      l_peak_count:=l_peak_count+1;
      l_peak(l_peak_count):=l_whole(command_.tic);
      l_peak_bytes(l_peak_count):=l_compressed_length;
    elsif command_.tic between 4401 and 5250 then
      l_quiet_count:=l_quiet_count+1;
      l_quiet(l_quiet_count):=l_whole(command_.tic);
      l_quiet_bytes(l_quiet_count):=l_compressed_length;
    end if;
    l_roundtrip:=doom_dvr_bind_roundtrip;
    if l_roundtrip<>1 then
      raise_application_error(-20796,'DVR codec round trip mismatch');
    end if;
    l_frame_sha:=retained_sha(false,c_frame_bytes);
    l_compressed_sha:=retained_sha(true,l_compressed_length);
    l_frame_chain:=dbms_crypto.hash(
      utl_raw.concat(l_frame_chain,l_frame_sha),dbms_crypto.hash_sh256);
    l_compressed_chain:=dbms_crypto.hash(
      utl_raw.concat(l_compressed_chain,l_compressed_sha),
      dbms_crypto.hash_sh256);
  end loop;
  l_wall_ms:=elapsed_ms(l_wall_start);
  l_get_ms:=(dbms_utility.get_time-l_get_start)*10;
  if abs(l_wall_ms-l_get_ms)>30 then l_suspects:=1;end if;
  if l_frontier<>c_tics then
    raise_application_error(-20796,'DVR codec frontier mismatch');
  end if;
  if lower(rawtohex(l_frame_chain))<>c_frame_chain or
      lower(rawtohex(l_compressed_chain))<>c_compressed_chain then
    raise_application_error(-20796,'DVR codec Node chain mismatch');
  end if;
  quicksort(l_whole,1,c_tics);quicksort(l_whole_bytes,1,c_tics);
  quicksort(l_peak,1,l_peak_count);quicksort(l_peak_bytes,1,l_peak_count);
  quicksort(l_quiet,1,l_quiet_count);quicksort(l_quiet_bytes,1,l_quiet_count);
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_after from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  dbms_output.put_line(
    'PMLE_OCI_DVR_CODEC|PASS|classification=POST_RELEASE_DVR_GATE'||
    '|codec=DOOM_DFR1_RLE|version=1|tics='||c_tics||
    '|whole_compress_p50_ms='||
      to_char(l_whole(ceil(c_tics*.5)),'FM9999990.000')||
    '|whole_compress_p95_ms='||
      to_char(l_whole(ceil(c_tics*.95)),'FM9999990.000')||
    '|whole_ratio_p50='||
      to_char(l_whole_bytes(ceil(c_tics*.5))/c_frame_bytes,'FM0.000000')||
    '|whole_ratio_p95='||
      to_char(l_whole_bytes(ceil(c_tics*.95))/c_frame_bytes,'FM0.000000')||
    '|peak_compress_p50_ms='||
      to_char(l_peak(ceil(l_peak_count*.5)),'FM9999990.000')||
    '|peak_compress_p95_ms='||
      to_char(l_peak(ceil(l_peak_count*.95)),'FM9999990.000')||
    '|peak_ratio_p50='||
      to_char(l_peak_bytes(ceil(l_peak_count*.5))/c_frame_bytes,'FM0.000000')||
    '|peak_ratio_p95='||
      to_char(l_peak_bytes(ceil(l_peak_count*.95))/c_frame_bytes,'FM0.000000')||
    '|quiet_compress_p50_ms='||
      to_char(l_quiet(ceil(l_quiet_count*.5)),'FM9999990.000')||
    '|quiet_compress_p95_ms='||
      to_char(l_quiet(ceil(l_quiet_count*.95)),'FM9999990.000')||
    '|quiet_ratio_p50='||
      to_char(l_quiet_bytes(ceil(l_quiet_count*.5))/c_frame_bytes,'FM0.000000')||
    '|quiet_ratio_p95='||
      to_char(l_quiet_bytes(ceil(l_quiet_count*.95))/c_frame_bytes,'FM0.000000')||
    '|wall_ms='||to_char(l_wall_ms,'FM999999990.000')||
    '|get_time_ms='||to_char(l_get_ms,'FM999999990.000')||
    '|clock_suspects='||l_suspects||'|clock_exclusion_cap=0'||
    '|temporary_lobs_before='||l_temp_before||
    '|temporary_lobs_after='||l_temp_after||
    '|temporary_lobs_delta='||(l_temp_after-l_temp_before)||
    '|frame_chain_sha256='||lower(rawtohex(l_frame_chain))||
    '|compressed_chain_sha256='||lower(rawtohex(l_compressed_chain))||
    '|presentation_sha256='||l_artifact_sha||
    '|codec_sha256='||l_codec_sha||
    '|stream_sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085'||
    '|compress_gate='||
      case when l_whole(ceil(c_tics*.95))<=5
        and l_peak(ceil(l_peak_count*.95))<=5
        and l_quiet(ceil(l_quiet_count*.95))<=5
        and l_temp_after=l_temp_before and l_suspects=0
      then 'PASS' else 'FAIL' end);
  doom_dvr_bind_release;
  commit;
exception when others then
  begin doom_dvr_bind_release;exception when others then null;end;
  rollback;raise;
end;
/
