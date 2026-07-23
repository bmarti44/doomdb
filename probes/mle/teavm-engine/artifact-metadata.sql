whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited

declare
  l_source blob;l_tables blob;
begin
  select source_blob,table_pack_blob into l_source,l_tables
    from doom_teavm_sim_source;
  dbms_output.put_line('PMLE_ARTIFACT|source_bytes='||dbms_lob.getlength(l_source)||
    '|source_sha256='||lower(rawtohex(dbms_crypto.hash(
      l_source,dbms_crypto.hash_sh256)))||
    '|table_bytes='||dbms_lob.getlength(l_tables)||
    '|table_sha256='||lower(rawtohex(dbms_crypto.hash(
      l_tables,dbms_crypto.hash_sh256))));
end;
/
