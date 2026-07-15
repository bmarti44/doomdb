whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback

alter session set nls_numeric_characters = '.,';
alter session set nls_territory = 'AMERICA';
alter session set nls_language = 'AMERICAN';
alter session set time_zone = 'UTC';

begin
  execute immediate 'drop table transport_probe_tx purge';
exception
  when others then
    if sqlcode != -942 then raise; end if;
end;
/

create table transport_probe_tx (
  id number generated always as identity primary key,
  marker varchar2(64) not null
);

create or replace package transport_probe_api authid definer as
  procedure echo_contract(
    p_number      in  number,
    p_text        in  clob,
    p_out_varchar out varchar2,
    p_out_clob    out clob,
    p_out_blob    out blob);

  procedure fail_after_write(
    p_marker      in  varchar2,
    p_out_varchar out varchar2);

  procedure transaction_count(p_count out number);

  procedure sized_payload(
    p_uncompressed_bytes in  number,
    p_out_blob           out blob);
end transport_probe_api;
/

create or replace package body transport_probe_api as
  function gzip_text(p_text clob) return blob is
    l_raw  raw(32767);
    l_src  blob;
    l_gzip blob;
    l_pos  pls_integer := 1;
    l_len  pls_integer := dbms_lob.getlength(p_text);
  begin
    dbms_lob.createtemporary(l_src, true, dbms_lob.call);
    while l_pos <= l_len loop
      l_raw := utl_raw.cast_to_raw(dbms_lob.substr(p_text, least(8000, l_len-l_pos+1), l_pos));
      dbms_lob.writeappend(l_src, utl_raw.length(l_raw), l_raw);
      l_pos := l_pos + least(8000, l_len-l_pos+1);
    end loop;
    l_gzip := utl_compress.lz_compress(l_src, 9);
    dbms_lob.freetemporary(l_src);
    return l_gzip;
  end gzip_text;

  procedure echo_contract(
    p_number      in  number,
    p_text        in  clob,
    p_out_varchar out varchar2,
    p_out_clob    out clob,
    p_out_blob    out blob) is
    l_json clob;
  begin
    p_out_varchar := to_char(
      p_number,
      'FM99999999999999999999999999999999999990D99999999999999999999',
      'NLS_NUMERIC_CHARACTERS=''.,''');
    p_out_clob := p_text;
    select json_object(
             'number' value p_number,
             'text' value p_text
             returning clob)
      into l_json
      from dual;
    p_out_blob := gzip_text(l_json);
  end echo_contract;

  procedure fail_after_write(
    p_marker      in  varchar2,
    p_out_varchar out varchar2) is
  begin
    insert into transport_probe_tx(marker) values (p_marker);
    p_out_varchar := 'must-not-return';
    raise_application_error(-20042, 'TRANSPORT_PROBE_ROLLBACK');
  end fail_after_write;

  procedure transaction_count(p_count out number) is
  begin
    select count(*) into p_count from transport_probe_tx;
  end transaction_count;

  procedure sized_payload(
    p_uncompressed_bytes in  number,
    p_out_blob           out blob) is
    l_doc   clob;
    l_chunk varchar2(4000);
  begin
    if p_uncompressed_bytes < 11 or p_uncompressed_bytes > 10485760 then
      raise_application_error(-20043, 'PAYLOAD_SIZE_OUT_OF_RANGE');
    end if;
    dbms_lob.createtemporary(l_doc, true, dbms_lob.call);
    dbms_random.seed(8675309);
    dbms_lob.writeappend(l_doc, 9, '{"data":"');
    while dbms_lob.getlength(l_doc) < p_uncompressed_bytes - 2 loop
      l_chunk := dbms_random.string(
        'X',
        least(4000, p_uncompressed_bytes - 2 - dbms_lob.getlength(l_doc)));
      dbms_lob.writeappend(l_doc, length(l_chunk), l_chunk);
    end loop;
    dbms_lob.writeappend(l_doc, 2, '"}');
    p_out_blob := gzip_text(l_doc);
    dbms_lob.freetemporary(l_doc);
  end sized_payload;
end transport_probe_api;
/

begin
  ords.enable_schema(
    p_enabled             => true,
    p_schema              => sys_context('USERENV', 'CURRENT_SCHEMA'),
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'doom',
    p_auto_rest_auth      => false);
  ords.enable_object(
    p_enabled        => true,
    p_schema         => sys_context('USERENV', 'CURRENT_SCHEMA'),
    p_object         => 'TRANSPORT_PROBE_API',
    p_object_type    => 'PACKAGE',
    p_object_alias   => 'transport_probe_api',
    p_auto_rest_auth => false);
  commit;
end;
/

show errors package transport_probe_api
show errors package body transport_probe_api
