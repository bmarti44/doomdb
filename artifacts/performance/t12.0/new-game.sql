whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited timing on pages 100 lines 220

declare
  l_session varchar2(32);
  l_payload blob;
  l_plain blob;
  l_document clob;
  l_destination_offset integer:=1;
  l_source_offset integer:=1;
  l_language_context integer:=0;
  l_warning integer;
begin
  delete from game_sessions;
  commit;
  doom_api.new_game(3,l_session,l_payload);
  l_plain:=utl_compress.lz_uncompress(l_payload);
  dbms_lob.createtemporary(l_document,true);
  dbms_lob.converttoclob(l_document,l_plain,dbms_lob.lobmaxsize,
    l_destination_offset,l_source_offset,nls_charset_id('AL32UTF8'),
    l_language_context,l_warning);
  dbms_output.put_line('SESSION '||l_session);
  dbms_output.put_line('PAYLOAD_BYTES '||dbms_lob.getlength(l_payload));
  dbms_output.put_line('STATE_SHA '||json_value(l_document,'$.state_sha'));
  dbms_output.put_line('FRAME_SHA '||json_value(l_document,'$.frame_sha'));
end;
/
