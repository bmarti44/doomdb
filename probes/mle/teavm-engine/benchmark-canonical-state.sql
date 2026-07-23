whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  l_wad blob;l_table_pack blob;l_blob blob;l_java_blob blob;
  l_length pls_integer;l_offset pls_integer;l_chunk raw(32767);l_loaded number;
  l_status varchar2(32767);l_started timestamp;l_hash raw(32);
  function elapsed_ms(p_started timestamp) return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin
    return extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000;
  end;
begin
  l_status:=doom_mocha_dispose;doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
   where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);l_loaded:=doom_teavm_sim_allocate(l_length);
  l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_table_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_table_pack);
  l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_table_pack,
      least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_status:=doom_teavm_sim_initialize;l_status:=doom_mocha_initialize;
  for sample in 1..5 loop
    l_started:=systimestamp;l_status:=doom_teavm_sim_canonical_state;
    dbms_output.put_line('PMLE_CANONICAL_STAGE|sample='||sample||'|stage=mle-digest|ms='||
      to_char(elapsed_ms(l_started),'FM9999990.000')||'|status='||l_status);
    l_started:=systimestamp;l_length:=doom_teavm_sim_canonical_length;
    dbms_output.put_line('PMLE_CANONICAL_STAGE|sample='||sample||'|stage=mle-material|ms='||
      to_char(elapsed_ms(l_started),'FM9999990.000')||'|bytes='||l_length);
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);l_offset:=0;
    l_started:=systimestamp;
    while l_offset<l_length loop
      l_chunk:=doom_teavm_sim_canonical_chunk(l_offset,
        least(32767,l_length-l_offset));
      dbms_lob.writeappend(l_blob,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    dbms_output.put_line('PMLE_CANONICAL_STAGE|sample='||sample||'|stage=mle-export|ms='||
      to_char(elapsed_ms(l_started),'FM9999990.000'));
    l_started:=systimestamp;l_hash:=dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256);
    dbms_output.put_line('PMLE_CANONICAL_STAGE|sample='||sample||'|stage=native-hash|ms='||
      to_char(elapsed_ms(l_started),'FM9999990.000'));
    dbms_lob.createtemporary(l_java_blob,true,dbms_lob.call);
    l_started:=systimestamp;l_status:=doom_mocha_canonical_blob(l_java_blob);
    dbms_output.put_line('PMLE_CANONICAL_STAGE|sample='||sample||'|stage=ojvm-material|ms='||
      to_char(elapsed_ms(l_started),'FM9999990.000'));
    dbms_lob.freetemporary(l_blob);dbms_lob.freetemporary(l_java_blob);
  end loop;
  doom_teavm_sim_release;l_status:=doom_mocha_dispose;
exception when others then
  begin doom_teavm_sim_release;exception when others then null;end;
  begin l_status:=doom_mocha_dispose;exception when others then null;end;
  raise;
end;
/
