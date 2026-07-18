whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  type numbers_t is table of number index by pls_integer;
  type hashes_t is table of pls_integer index by varchar2(64);
  l_values numbers_t;
  l_hashes hashes_t;
  l_frame blob;
  l_status varchar2(4000);
  l_value number;
  l_swap number;

  function field(p_status varchar2,p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');
    l_end pls_integer;
  begin
    if l_start=0 then raise_application_error(-20000,'missing '||p_name);end if;
    l_start:=l_start+length(p_name)+2;
    l_end:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_end=0 then length(p_status)+1 else l_end end-l_start);
  end;

  function percentile_index(p_count number,p_percent number) return number is
  begin
    return greatest(1,least(p_count,ceil(p_count*p_percent/100)));
  end;
begin
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  l_status:=doom_mocha_new_game(2,1,1);
  if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;

  for l_sample in -29..300 loop
    l_status:=doom_mocha_step_controls_frame(
      0,1,0,1,case when mod(l_sample+29,8)=0 then 1 else 0 end,
      0,0,0,0,0,l_frame);
    if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;
    if l_sample>0 then
      l_values(l_sample):=to_number(field(l_status,'elapsedMicros'));
      l_hashes(field(l_status,'frameSha256')):=1;
    end if;
  end loop;

  -- The bounded 300-value insertion sort keeps the gate self-contained.
  for l_index in 2..300 loop
    l_value:=l_values(l_index);
    declare l_scan pls_integer:=l_index-1; begin
      while l_scan>=1 and l_values(l_scan)>l_value loop
        l_values(l_scan+1):=l_values(l_scan);
        l_scan:=l_scan-1;
      end loop;
      l_values(l_scan+1):=l_value;
    end;
  end loop;

  dbms_output.put_line('PASS MOCHADOOM-CONTROL-PATH samples=300'||
    ' uniqueFrames='||l_hashes.count||
    ' p50Micros='||l_values(percentile_index(300,50))||
    ' p95Micros='||l_values(percentile_index(300,95))||
    ' p99Micros='||l_values(percentile_index(300,99))||
    ' maxMicros='||l_values(300)||
    ' frameBytes='||dbms_lob.getlength(l_frame));
  dbms_lob.freetemporary(l_frame);
end;
/
