whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_payload blob;l_plain blob;l_status varchar2(4000);
  l_state_sha varchar2(64):=rpad('0',64,'0');l_audio varchar2(4000);
  l_audio_length number;l_events number:=0;l_pistol number:=0;

  function field(p_status varchar2,p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');l_end pls_integer;
  begin
    l_start:=l_start+length(p_name)+2;l_end:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_end=0 then length(p_status)+1 else l_end end-l_start);
  end;
begin
  dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
  l_status:=doom_mocha_new_game(2,1,1);
  for l_tic in 1..24 loop
    l_status:=doom_mocha_step_controls_payload(
      0,0,0,0,1,0,0,0,0,0,0,l_state_sha,l_payload);
    if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;
    l_state_sha:=field(l_status,'stateSha256');
    l_plain:=doom_mocha_payload_plain(l_payload);
    l_audio_length:=to_number(
      rawtohex(dbms_lob.substr(l_plain,2,139)),'XXXX');
    l_audio:=utl_raw.cast_to_varchar2(
      dbms_lob.substr(l_plain,l_audio_length,141));
    if l_audio<>'[]' then
      l_events:=l_events+1;
      if instr(l_audio,'"DSPISTOL"')>0 and
         instr(l_audio,'[['||l_tic||',0,')=1 then l_pistol:=l_pistol+1;end if;
    end if;
  end loop;
  if l_pistol<1 then
    raise_application_error(-20000,'pistol audio event missing events='||l_events);
  end if;
  dbms_output.put_line('PASS MOCHADOOM-AUDIO tics=24 eventTics='||l_events||
    ' pistolEventTics='||l_pistol||' stateSha='||l_state_sha);
  dbms_lob.freetemporary(l_payload);
  l_status:=doom_mocha_dispose;
end;
/
