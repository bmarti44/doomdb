whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_players constant pls_integer:=4;c_checkpoint_tic constant pls_integer:=100;
  c_final_tic constant pls_integer:=430;
  l_wad blob;l_pack blob;l_checkpoint blob;l_mle_blob blob;l_java_blob blob;
  l_length pls_integer;l_checkpoint_length pls_integer;
  l_offset pls_integer;l_chunk raw(32767);l_loaded number;
  l_mle_tic number;l_java varchar2(32767);l_restore varchar2(32767);
  l_hex varchar2(64);l_commands raw(32);l_started timestamp;l_restore_ms number;
  function elapsed_ms(p_value interval day to second)return number is
  begin return extract(day from p_value)*86400000+
    extract(hour from p_value)*3600000+extract(minute from p_value)*60000+
    extract(second from p_value)*1000;end;
  function commands(p_tic number)return raw is
  begin
    l_hex:=
      (case when mod(p_tic,5)=0 then '19' else '00' end)||'000000000000'||
        (case when mod(p_tic,23)=0 then '01' else '00' end)||
      '00'||(case when mod(p_tic,7)=0 then 'E8' else '00' end)||'000000000000'||
      '0000'||(case when mod(p_tic,11)=0 then 'FD80' else '0000' end)||'00000000'||
      (case when mod(p_tic,13)=0 then 'F0' else '00' end)||'00000000000000';
    return hextoraw(l_hex);
  end;
  procedure load_assets is
  begin
    select payload_bytes into l_wad from doom_engine_artifact where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    select table_pack_blob into l_pack from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_pack);l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;
  procedure compare_canonical(p_tic number) is
    l_size pls_integer;l_at pls_integer:=0;l_raw raw(32767);
    l_status varchar2(32767);l_mle_sha raw(32);l_java_sha raw(32);
  begin
    dbms_lob.createtemporary(l_mle_blob,true,dbms_lob.call);
    dbms_lob.createtemporary(l_java_blob,true,dbms_lob.call);
    l_size:=doom_teavm_sim_canonical_length;
    while l_at<l_size loop
      l_raw:=doom_teavm_sim_canonical_chunk(l_at,least(32767,l_size-l_at));
      dbms_lob.writeappend(l_mle_blob,utl_raw.length(l_raw),l_raw);
      l_at:=l_at+utl_raw.length(l_raw);
    end loop;
    l_status:=doom_mocha_canonical_blob(l_java_blob);
    if l_status not like 'ok|%' or dbms_lob.getlength(l_java_blob)<>l_size then
      raise_application_error(-20796,'tic '||p_tic||' canonical material failure');end if;
    l_mle_sha:=dbms_crypto.hash(l_mle_blob,dbms_crypto.hash_sh256);
    l_java_sha:=dbms_crypto.hash(l_java_blob,dbms_crypto.hash_sh256);
    if l_mle_sha<>l_java_sha then raise_application_error(-20796,
      'tic '||p_tic||' canonical SHA MLE='||lower(rawtohex(l_mle_sha))||
      ' OJVM='||lower(rawtohex(l_java_sha)));end if;
    dbms_lob.freetemporary(l_mle_blob);dbms_lob.freetemporary(l_java_blob);
  exception when others then
    if dbms_lob.istemporary(l_mle_blob)=1 then dbms_lob.freetemporary(l_mle_blob);end if;
    if dbms_lob.istemporary(l_java_blob)=1 then dbms_lob.freetemporary(l_java_blob);end if;raise;
  end;
  procedure step_both(p_tic number) is
  begin
    l_commands:=commands(p_tic);l_mle_tic:=doom_teavm_sim_multi_step(c_players,l_commands);
    l_java:=doom_mocha_multiplayer_sim_step(c_players,l_hex);
    if l_mle_tic<>p_tic or l_java not like 'ok|%' then
      raise_application_error(-20795,'tic '||p_tic||' MLE='||l_mle_tic||' OJVM='||l_java);end if;
  end;
begin
  l_java:=doom_mocha_dispose;doom_teavm_sim_release;load_assets;
  l_java:=doom_teavm_sim_multi_init(c_players);
  l_java:=doom_mocha_multiplayer_sim_init(c_players);
  for tic in 1..c_checkpoint_tic loop step_both(tic);end loop;
  compare_canonical(c_checkpoint_tic);
  dbms_lob.createtemporary(l_checkpoint,true,dbms_lob.call);
  l_checkpoint_length:=doom_teavm_sim_checkpoint_length;l_offset:=0;
  while l_offset<l_checkpoint_length loop
    l_chunk:=doom_teavm_sim_checkpoint_chunk(
      l_offset,least(32767,l_checkpoint_length-l_offset));
    dbms_lob.writeappend(l_checkpoint,utl_raw.length(l_chunk),l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if dbms_lob.getlength(l_checkpoint)<>l_checkpoint_length then
    raise_application_error(-20797,'short checkpoint export expected='||
      l_checkpoint_length||' actual='||dbms_lob.getlength(l_checkpoint));end if;

  doom_teavm_sim_release;load_assets;l_java:=doom_teavm_sim_multi_init(c_players);
  l_loaded:=doom_teavm_sim_restore_allocate(l_checkpoint_length);l_offset:=0;
  while l_offset<l_checkpoint_length loop
    l_chunk:=dbms_lob.substr(
      l_checkpoint,least(32767,l_checkpoint_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_restore_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if l_loaded<>l_checkpoint_length or l_offset<>l_checkpoint_length then
    raise_application_error(-20797,'short checkpoint load expected='||
      l_checkpoint_length||' loaded='||l_loaded||' offset='||l_offset);end if;
  l_started:=systimestamp;l_restore:=doom_teavm_sim_restore(c_checkpoint_tic);
  l_restore_ms:=elapsed_ms(systimestamp-l_started);
  if l_restore not like 'state=restored|%' then
    raise_application_error(-20798,substr(l_restore,1,1800));end if;
  compare_canonical(c_checkpoint_tic);
  for tic in c_checkpoint_tic+1..c_final_tic loop
    step_both(tic);
    if mod(tic,50)=0 or tic=c_final_tic then compare_canonical(tic);end if;
  end loop;
  dbms_output.put_line('PMLE_TEAVM_MULTI_RECOVERY|PASS|players='||c_players||
    '|fresh_context=1|checkpoint_tic='||c_checkpoint_tic||
    '|checkpoint_bytes='||l_checkpoint_length||'|restore_ms='||round(l_restore_ms,3)||
    '|continued_tics='||(c_final_tic-c_checkpoint_tic)||'|final_tic='||c_final_tic);
  dbms_lob.freetemporary(l_checkpoint);doom_teavm_sim_release;l_java:=doom_mocha_dispose;
exception when others then
  if dbms_lob.istemporary(l_checkpoint)=1 then dbms_lob.freetemporary(l_checkpoint);end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_java:=doom_mocha_dispose;exception when others then null;end;raise;
end;
/
