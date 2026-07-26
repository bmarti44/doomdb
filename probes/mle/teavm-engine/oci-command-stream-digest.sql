whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set trimspool on serveroutput on size unlimited
declare
  c_stream constant varchar2(64):='live-dm-2026-07-23';
  c_tics constant pls_integer:=5250;
  c_expected_final constant varchar2(64):=
    'b3f667c9395455fd42e31586dd79006fc9c091132cb09c8b1f4627a7d93a9907';
  c_expected_cumulative constant varchar2(64):=
    '__EXPECTED_CUMULATIVE_SHA256__';
  l_wad blob;l_tables blob;l_canonical blob;
  l_chunk raw(32767);l_length pls_integer;l_offset pls_integer;
  l_loaded number;l_tic number:=0;l_state varchar2(32767);
  l_state_sha raw(32);l_cumulative raw(32):=hextoraw(rpad('0',64,'0'));

  procedure load_blob(
    p_blob blob,p_allocate varchar2,p_write varchar2
  ) is
  begin
    -- The two supported asset channels have distinct call specs. Keep the
    -- branch explicit so dynamic SQL never enters the measured digest loop.
    l_length:=dbms_lob.getlength(p_blob);l_offset:=0;
    if p_allocate='IWAD' then
      l_loaded:=doom_teavm_sim_allocate(l_length);
    else
      l_loaded:=doom_teavm_sim_table_allocate(l_length);
    end if;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(32767,l_length-l_offset),l_offset+1);
      if p_write='IWAD' then
        l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
      else
        l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
      end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;

  procedure hash_canonical(p_tic pls_integer) is
  begin
    dbms_lob.trim(l_canonical,0);
    l_length:=doom_teavm_sim_canonical_length;l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=doom_teavm_sim_canonical_chunk(
        l_offset,least(32767,l_length-l_offset));
      dbms_lob.writeappend(
        l_canonical,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    l_state_sha:=dbms_crypto.hash(
      l_canonical,dbms_crypto.hash_sh256);
    l_cumulative:=dbms_crypto.hash(
      utl_raw.concat(
        l_cumulative,
        utl_raw.cast_from_binary_integer(p_tic,1),
        l_state_sha),
      dbms_crypto.hash_sh256);
  end;
begin
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  select table_pack_blob into l_tables from doom_teavm_sim_source;
  load_blob(l_wad,'IWAD','IWAD');
  load_blob(l_tables,'TABLES','TABLES');
  l_state:=doom_teavm_sim_multi_init_game(2,1,3,1,1);
  if l_state not like 'state=multiplayer-initialized|gametic=0|%' then
    raise_application_error(-20796,'OCI digest initialization mismatch');
  end if;
  dbms_lob.createtemporary(l_canonical,true,dbms_lob.call);
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector
    from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_tics
    order by tic
  ) loop
    if command_.tic<>l_tic+1 then
      raise_application_error(-20796,'OCI digest stream gap');
    end if;
    l_tic:=doom_teavm_sim_authority_step(
      2,command_.membership,command_.command_vector);
    if l_tic<>command_.tic then
      raise_application_error(-20796,'OCI digest frontier mismatch');
    end if;
    hash_canonical(l_tic);
    if mod(l_tic,500)=0 then
      dbms_output.put_line(
        'PMLE_COMMAND_DIGEST_PROGRESS|venue=OCI_ADB|tic='||l_tic||
        '|cumulative_sha256='||lower(rawtohex(l_cumulative)));
    end if;
  end loop;
  if l_tic<>c_tics then
    raise_application_error(-20796,'OCI digest tic count mismatch');
  end if;
  if lower(rawtohex(l_state_sha))<>c_expected_final then
    raise_application_error(-20796,'OCI terminal canonical SHA mismatch');
  end if;
  if lower(rawtohex(l_cumulative))<>c_expected_cumulative then
    raise_application_error(-20796,'OCI cumulative SHA mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_COMMAND_DIGEST|PASS|venue=OCI_ADB|tics='||l_tic||
    '|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'||
    '|stream_sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085'||
    '|canonical_sha256='||lower(rawtohex(l_state_sha))||
    '|cumulative_sha256='||lower(rawtohex(l_cumulative)));
  dbms_lob.freetemporary(l_canonical);
  doom_teavm_sim_release;
exception when others then
  if dbms_lob.istemporary(l_canonical)=1 then
    dbms_lob.freetemporary(l_canonical);
  end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  raise;
end;
/
