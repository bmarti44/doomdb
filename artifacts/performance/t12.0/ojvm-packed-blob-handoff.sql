whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited feedback off timing off

create or replace and compile java source named doom_blob_handoff_probe_src as
import java.io.OutputStream;
import java.sql.Blob;

public final class DoomBlobHandoffProbe {
  private static final int LENGTH = 42140;
  private static final byte[] BYTES = new byte[LENGTH];
  static {
    for (int index = 0; index < BYTES.length; index++)
      BYTES[index] = (byte) ((index * 73 + 19) & 255);
  }

  public static void direct(Blob payload) throws Exception {
    payload.truncate(0);
    if (payload.setBytes(1, BYTES) != BYTES.length)
      throw new IllegalStateException("short direct BLOB write");
  }

  public static void chunked(Blob payload) throws Exception {
    payload.truncate(0);
    int first = payload.setBytes(1, BYTES, 0, 32767);
    int second = payload.setBytes(32768, BYTES, 32767, BYTES.length - 32767);
    if (first + second != BYTES.length)
      throw new IllegalStateException("short chunked BLOB write");
  }

  public static void stream(Blob payload) throws Exception {
    payload.truncate(0);
    OutputStream output = payload.setBinaryStream(1);
    output.write(BYTES);
    output.close();
  }
}
/

create or replace procedure doom_blob_probe_direct(p_payload in blob) as
language java name 'DoomBlobHandoffProbe.direct(java.sql.Blob)';
/
create or replace procedure doom_blob_probe_chunked(p_payload in blob) as
language java name 'DoomBlobHandoffProbe.chunked(java.sql.Blob)';
/
create or replace procedure doom_blob_probe_stream(p_payload in blob) as
language java name 'DoomBlobHandoffProbe.stream(java.sql.Blob)';
/

declare
  type number_table is table of number index by binary_integer;
  l_ms number_table;
  l_payload blob;
  l_expected raw(32);
  l_started timestamp;
  l_swap number;
  l_p95 number;
  c_warm constant pls_integer := 200;
  c_samples constant pls_integer := 1500;

  function elapsed_ms(p_started timestamp) return number is
    l_elapsed interval day to second := systimestamp-p_started;
  begin
    return extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000;
  end;

  procedure invoke(p_mode varchar2) is
  begin
    case p_mode
      when 'DIRECT' then doom_blob_probe_direct(l_payload);
      when 'CHUNKED' then doom_blob_probe_chunked(l_payload);
      when 'STREAM' then doom_blob_probe_stream(l_payload);
      else raise_application_error(-20000,'unknown handoff mode');
    end case;
  end;

  procedure benchmark(p_mode varchar2) is
  begin
    for i in 1..c_warm loop invoke(p_mode); end loop;
    for i in 1..c_samples loop
      l_started := systimestamp;
      invoke(p_mode);
      l_ms(i) := elapsed_ms(l_started);
    end loop;
    for i in 1..c_samples-1 loop
      for j in i+1..c_samples loop
        if l_ms(j)<l_ms(i) then
          l_swap:=l_ms(i);l_ms(i):=l_ms(j);l_ms(j):=l_swap;
        end if;
      end loop;
    end loop;
    l_p95:=l_ms(ceil(c_samples*.95));
    if dbms_lob.getlength(l_payload)<>42140 or
       dbms_crypto.hash(l_payload,dbms_crypto.hash_sh256)<>l_expected then
      raise_application_error(-20001,p_mode||' BLOB bytes differ');
    end if;
    dbms_output.put_line('BLOB_'||p_mode||'_P50_MS='||
      to_char(l_ms(ceil(c_samples*.50)),'FM9999990.000000'));
    dbms_output.put_line('BLOB_'||p_mode||'_P95_MS='||
      to_char(l_p95,'FM9999990.000000'));
    dbms_output.put_line('BLOB_'||p_mode||'_P99_MS='||
      to_char(l_ms(ceil(c_samples*.99)),'FM9999990.000000'));
    if l_p95>3 then
      raise_application_error(-20002,p_mode||' BLOB handoff exceeded 3 ms p95');
    end if;
  end;
begin
  dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
  doom_blob_probe_direct(l_payload);
  l_expected:=dbms_crypto.hash(l_payload,dbms_crypto.hash_sh256);
  benchmark('DIRECT');
  benchmark('CHUNKED');
  benchmark('STREAM');
  dbms_output.put_line('BLOB_HANDOFF_BYTES='||dbms_lob.getlength(l_payload));
  dbms_output.put_line('BLOB_HANDOFF_SHA256='||lower(rawtohex(l_expected)));
  dbms_lob.freetemporary(l_payload);
end;
/

drop procedure doom_blob_probe_stream;
drop procedure doom_blob_probe_chunked;
drop procedure doom_blob_probe_direct;
drop java source doom_blob_handoff_probe_src;

select count(*) as blob_probe_objects from user_objects
where upper(object_name) like '%DOOM%BLOB%PROBE%';
select count(*) as invalid_objects from user_objects where status<>'VALID';
