whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off lines 32767 trimspool on serveroutput on size unlimited

declare
  c_players constant pls_integer:=2;
  c_leave_tic constant pls_integer:=41;
  c_checkpoint_tic constant pls_integer:=60;
  c_final_tic constant pls_integer:=100;
  c_mle_sha constant varchar2(64):='06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0';
  c_ojvm_jar_sha constant varchar2(64):='2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74';
  l_wad blob;l_pack blob;l_checkpoint blob;l_mle_blob blob;l_java_blob blob;
  l_length pls_integer;l_offset pls_integer;l_loaded number;l_checkpoint_length pls_integer;
  l_chunk raw(32767);l_commands raw(32);l_status varchar2(32767);l_mle_tic number;

  procedure load_assets is
  begin
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);l_loaded:=doom_teavm_sim_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    select table_pack_blob into l_pack from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_pack);l_loaded:=doom_teavm_sim_table_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;

  function commands(p_tic number,p_membership number) return raw is
    l_hex varchar2(64);
  begin
    l_hex:=(case when mod(p_tic,5)=0 then '19' else '00' end)||
      '000000000000'||(case when mod(p_tic,23)=0 then '01' else '00' end);
    if bitand(p_membership,2)=2 then
      l_hex:=l_hex||'00'||(case when mod(p_tic,7)=0 then 'E8' else '00' end)||
        '000000000000';
    else l_hex:=l_hex||rpad('00',16,'0');end if;
    l_hex:=l_hex||rpad('00',32,'0');
    return hextoraw(l_hex);
  end;

  procedure compare_canonical(p_tic number) is
    l_size pls_integer;l_at pls_integer:=0;l_raw raw(32767);
    l_java_status varchar2(32767);l_mle_sha raw(32);l_java_sha raw(32);
  begin
    dbms_lob.createtemporary(l_mle_blob,true,dbms_lob.call);
    dbms_lob.createtemporary(l_java_blob,true,dbms_lob.call);
    l_size:=doom_teavm_sim_canonical_length;
    while l_at<l_size loop
      l_raw:=doom_teavm_sim_canonical_chunk(l_at,least(32767,l_size-l_at));
      dbms_lob.writeappend(l_mle_blob,utl_raw.length(l_raw),l_raw);
      l_at:=l_at+utl_raw.length(l_raw);
    end loop;
    l_java_status:=doom_mocha_canonical_blob(l_java_blob);
    if l_java_status not like 'ok|%' or dbms_lob.getlength(l_java_blob)<>l_size then
      raise_application_error(-20796,'membership tic '||p_tic||' material MLE_bytes='||
        l_size||' OJVM_bytes='||dbms_lob.getlength(l_java_blob)||' OJVM_status='||
        substr(l_java_status,1,500));end if;
    l_mle_sha:=dbms_crypto.hash(l_mle_blob,dbms_crypto.hash_sh256);
    l_java_sha:=dbms_crypto.hash(l_java_blob,dbms_crypto.hash_sh256);
    if l_mle_sha<>l_java_sha then raise_application_error(-20796,
      'membership tic '||p_tic||' MLE='||lower(rawtohex(l_mle_sha))||
      ' OJVM='||lower(rawtohex(l_java_sha)));end if;
    dbms_lob.freetemporary(l_mle_blob);dbms_lob.freetemporary(l_java_blob);
  exception when others then
    if dbms_lob.istemporary(l_mle_blob)=1 then dbms_lob.freetemporary(l_mle_blob);end if;
    if dbms_lob.istemporary(l_java_blob)=1 then dbms_lob.freetemporary(l_java_blob);end if;
    raise;
  end;

  procedure step_both(p_tic number,p_membership number) is
  begin
    l_commands:=commands(p_tic,p_membership);
    l_mle_tic:=doom_teavm_sim_authority_step(c_players,p_membership,l_commands);
    l_status:=doom_mocha_multiplayer_sim_membership_step(
      c_players,p_membership,lower(rawtohex(l_commands)));
    if l_mle_tic<>p_tic or l_status not like 'ok|%' then
      raise_application_error(-20796,'membership step '||p_tic||' MLE='||
        l_mle_tic||' OJVM='||substr(l_status,1,500));end if;
    compare_canonical(p_tic);
  end;
begin
  select case when lower(rawtohex(dbms_crypto.hash(
      source_blob,dbms_crypto.hash_sh256)))=c_mle_sha then 1 else 0 end
    into l_loaded from doom_teavm_sim_source;
  if l_loaded<>1 then raise_application_error(-20796,'membership MLE artifact SHA');end if;
  l_status:=doom_mocha_dispose;doom_teavm_sim_release;load_assets;
  l_status:=doom_teavm_sim_multi_init_game(c_players,0,3,1,1);
  l_status:=doom_mocha_multiplayer_sim_init_skill(c_players,3);
  if l_status not like 'ok|%' then raise_application_error(-20796,l_status);end if;
  compare_canonical(0);
  for tic in 1..c_checkpoint_tic loop
    step_both(tic,case when tic<c_leave_tic then 3 else 1 end);
  end loop;

  l_checkpoint_length:=doom_teavm_sim_checkpoint_length;
  dbms_lob.createtemporary(l_checkpoint,true,dbms_lob.call);l_offset:=0;
  while l_offset<l_checkpoint_length loop
    l_chunk:=doom_teavm_sim_checkpoint_chunk(
      l_offset,least(32767,l_checkpoint_length-l_offset));
    dbms_lob.writeappend(l_checkpoint,utl_raw.length(l_chunk),l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  doom_teavm_sim_release;load_assets;
  l_status:=doom_teavm_sim_multi_init_game(c_players,0,3,1,1);
  l_loaded:=doom_teavm_sim_restore_allocate(l_checkpoint_length);l_offset:=0;
  while l_offset<l_checkpoint_length loop
    l_chunk:=dbms_lob.substr(l_checkpoint,
      least(32767,l_checkpoint_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_restore_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_status:=doom_teavm_sim_restore(c_checkpoint_tic);
  if l_status not like 'state=restored|gametic=60|%' then
    raise_application_error(-20796,'membership restore '||l_status);end if;
  compare_canonical(c_checkpoint_tic);
  for tic in c_checkpoint_tic+1..c_final_tic loop step_both(tic,3);end loop;
  dbms_output.put_line('PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS|players=2'||
    '|leave_tic='||c_leave_tic||'|neutral_tics='||(c_checkpoint_tic-c_leave_tic+1)||
    '|checkpoint_tic='||c_checkpoint_tic||'|rejoin_tic='||(c_checkpoint_tic+1)||
    '|final_tic='||c_final_tic||'|deep_every=1|mle_sha256='||c_mle_sha||
    '|ojvm_jar_sha256='||c_ojvm_jar_sha);
  dbms_lob.freetemporary(l_checkpoint);doom_teavm_sim_release;l_status:=doom_mocha_dispose;
exception when others then
  if dbms_lob.istemporary(l_checkpoint)=1 then dbms_lob.freetemporary(l_checkpoint);end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_status:=doom_mocha_dispose;exception when others then null;end;
  raise;
end;
/
