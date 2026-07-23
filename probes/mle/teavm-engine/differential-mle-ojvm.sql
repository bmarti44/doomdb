whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_tics constant pls_integer:=330;
  l_wad blob;l_table_pack blob;l_length pls_integer;l_offset pls_integer:=0;l_chunk raw(32767);
  l_loaded number;l_mle varchar2(32767);l_java varchar2(32767);
  l_forward number;l_side number;l_turn number;l_buttons number;
  function field(p_status varchar2,p_name varchar2)return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');l_finish pls_integer;
  begin
    if l_start=0 then raise_application_error(-20792,'missing field '||p_name);end if;
    l_start:=l_start+length(p_name)+2;l_finish:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_finish=0 then length(p_status)+1 else l_finish end-l_start);
  end;
  procedure equal_field(
    p_tic number,p_mle_name varchar2,p_java_name varchar2) is
    l_left varchar2(4000):=field(l_mle,p_mle_name);
    l_right varchar2(4000):=field(l_java,p_java_name);
  begin
    if l_left<>l_right then
      raise_application_error(-20793,'tic '||p_tic||' field '||p_mle_name||
        ' MLE='||l_left||' OJVM='||l_right);
    end if;
  end;
  procedure compare_state(p_tic number) is
  begin
    equal_field(p_tic,'gametic','tic');
    equal_field(p_tic,'leveltime','levelTime');
    equal_field(p_tic,'randomIndex','randomIndex');
    equal_field(p_tic,'playerX','playerX');
    equal_field(p_tic,'playerY','playerY');
    equal_field(p_tic,'playerZ','playerZ');
    equal_field(p_tic,'playerAngle','playerAngle');
    equal_field(p_tic,'playerHealth','playerHealth');
    equal_field(p_tic,'viewZ','viewZ');
    equal_field(p_tic,'armor','armor');
    equal_field(p_tic,'readyWeapon','readyWeapon');
    equal_field(p_tic,'kills','kills');
    equal_field(p_tic,'items','items');
    equal_field(p_tic,'secrets','secrets');
  end;
  procedure compare_canonical_state(p_tic number) is
    l_mle_blob blob;l_java_blob blob;l_mle_length pls_integer;
    l_canonical_offset pls_integer:=0;l_canonical_chunk raw(32767);
    l_java_status varchar2(32767);l_mle_hash raw(32);l_java_hash raw(32);
  begin
    dbms_lob.createtemporary(l_mle_blob,true,dbms_lob.call);
    dbms_lob.createtemporary(l_java_blob,true,dbms_lob.call);
    l_mle_length:=doom_teavm_sim_canonical_length;
    while l_canonical_offset<l_mle_length loop
      l_canonical_chunk:=doom_teavm_sim_canonical_chunk(
        l_canonical_offset,least(32767,l_mle_length-l_canonical_offset));
      dbms_lob.writeappend(l_mle_blob,utl_raw.length(l_canonical_chunk),
        l_canonical_chunk);
      l_canonical_offset:=l_canonical_offset+utl_raw.length(l_canonical_chunk);
    end loop;
    l_java_status:=doom_mocha_canonical_blob(l_java_blob);
    if l_java_status not like 'ok|%' then
      raise_application_error(-20795,l_java_status);
    end if;
    if dbms_lob.getlength(l_java_blob)<>l_mle_length then
      raise_application_error(-20796,'tic '||p_tic||' canonical length MLE='||
        l_mle_length||' OJVM='||dbms_lob.getlength(l_java_blob));
    end if;
    l_mle_hash:=dbms_crypto.hash(l_mle_blob,dbms_crypto.hash_sh256);
    l_java_hash:=dbms_crypto.hash(l_java_blob,dbms_crypto.hash_sh256);
    if l_java_hash<>l_mle_hash then
      raise_application_error(-20796,'tic '||p_tic||' canonical SHA MLE='||
        lower(rawtohex(l_mle_hash))||' OJVM='||lower(rawtohex(l_java_hash)));
    end if;
    dbms_lob.freetemporary(l_mle_blob);dbms_lob.freetemporary(l_java_blob);
  exception when others then
    if dbms_lob.istemporary(l_mle_blob)=1 then dbms_lob.freetemporary(l_mle_blob);end if;
    if dbms_lob.istemporary(l_java_blob)=1 then dbms_lob.freetemporary(l_java_blob);end if;
    raise;
  end;
begin
  l_java:=doom_mocha_dispose;
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
   where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_loaded:=doom_teavm_sim_allocate(l_length);
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20794,'IWAD load mismatch at '||l_offset);
    end if;
  end loop;
  select table_pack_blob into l_table_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_table_pack);l_offset:=0;
  l_loaded:=doom_teavm_sim_table_allocate(l_length);
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_table_pack,
      least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20794,'table pack load mismatch at '||l_offset);
    end if;
  end loop;
  l_mle:=doom_teavm_sim_initialize;
  l_java:=doom_mocha_initialize;
  if l_java not like 'ok|%' then raise_application_error(-20795,l_java);end if;
  compare_state(0);
  compare_canonical_state(0);
  for i in 1..c_tics loop
    l_forward:=case when mod(i,20)<14 then 25 else 0 end;
    l_side:=case when mod(i,31)<3 then 8 else 0 end;
    l_turn:=case when mod(i,17)<5 then 320 else 0 end;
    l_buttons:=case when mod(i,23)=0 then 1 else 0 end;
    l_mle:=doom_teavm_sim_step(l_forward,l_side,l_turn,l_buttons);
    l_java:=doom_mocha_step_simulation(l_forward,l_side,l_turn,l_buttons);
    if l_java not like 'ok|%' then raise_application_error(-20795,l_java);end if;
    compare_state(i);
    compare_canonical_state(i);
  end loop;
  dbms_output.put_line('PMLE_TEAVM_DIFFERENTIAL|PASS|tics='||c_tics||
    '|fields=14|canonical=native-sha256-save-world-plus-references|final_mle='||l_mle);
  doom_teavm_sim_release;l_java:=doom_mocha_dispose;
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_java:=doom_mocha_dispose;exception when others then null;end;
  raise;
end;
/
