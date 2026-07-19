whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  type numbers_t is table of number index by pls_integer;
  l_values numbers_t;l_payload blob;l_status varchar2(4000);
  l_state_sha varchar2(64):=rpad('0',64,'0');l_value number;

  function field(p_status varchar2,p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');l_end pls_integer;
  begin
    if l_start=0 then raise_application_error(-20000,'missing '||p_name);end if;
    l_start:=l_start+length(p_name)+2;l_end:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_end=0 then length(p_status)+1 else l_end end-l_start);
  end;
begin
  dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
  l_status:=doom_mocha_new_game(2,1,1);
  for l_index in 1..330 loop
    l_status:=doom_mocha_step_controls_payload(0,1,0,1,
      case when mod(l_index-1,8)=0 then 1 else 0 end,0,0,0,0,0,0,
      l_state_sha,l_payload);
    if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;
    l_state_sha:=field(l_status,'stateSha256');
    if l_index>30 then
      l_values(l_index-30):=to_number(field(l_status,'payloadElapsedMicros'));
    end if;
  end loop;
  for l_index in 2..300 loop
    l_value:=l_values(l_index);
    declare l_scan pls_integer:=l_index-1;begin
      while l_scan>=1 and l_values(l_scan)>l_value loop
        l_values(l_scan+1):=l_values(l_scan);l_scan:=l_scan-1;
      end loop;
      l_values(l_scan+1):=l_value;
    end;
  end loop;
  if utl_raw.cast_to_varchar2(dbms_lob.substr(
       doom_mocha_payload_plain(l_payload),4,1)) not in('DMF3','DMF4') then
    raise_application_error(-20000,'payload codec missing');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-PAYLOAD-PATH samples=300'||
    ' p50Micros='||l_values(150)||' p95Micros='||l_values(285)||
    ' p99Micros='||l_values(297)||' maxMicros='||l_values(300)||
    ' payloadBytes='||dbms_lob.getlength(l_payload)||
    ' stateSha='||l_state_sha);
  dbms_lob.freetemporary(l_payload);
end;
/
