whenever sqlerror exit failure rollback
set serveroutput on size unlimited heading off feedback off pages 0 lines 32767

declare
  commands blob;
  status varchar2(4000);
  expected_sha varchar2(64);
  piece raw(8);

  function field(p_status varchar2,p_name varchar2) return varchar2 is
  begin
    return regexp_substr(
      p_status,'(^|\|)'||p_name||'=([^|]*)',1,1,null,2);
  end;
begin
  dbms_lob.createtemporary(commands,true);
  status:=doom_mocha_initialize;
  if not status like 'ok|%' then
    raise_application_error(-20000,status);
  end if;

  for i in 0..69 loop
    piece:=hextoraw('19000000000000'||
      case when mod(i,8)=0 then '01' else '00' end);
    dbms_lob.writeappend(commands,8,piece);
    status:=doom_mocha_step(
      25,0,0,case when mod(i,8)=0 then 1 else 0 end);
    if not status like 'ok|%' then
      raise_application_error(-20000,status);
    end if;
  end loop;
  expected_sha:=field(status,'frameSha256');
  status:=doom_mocha_dispose;

  status:=doom_mocha_reconstruct(2,1,1,commands,expected_sha);
  if not status like 'ok|%' then
    raise_application_error(-20000,status);
  end if;
  if to_number(field(status,'replayedCommands'))<>70 or
     field(status,'commandSha256')<>
       'afb9740b82590f9678ababc1376ba6fd1d388130f39a1e060b9127b5d3235140' then
    raise_application_error(-20000,'reconstruction metadata mismatch');
  end if;

  dbms_output.put_line('PASS MOCHADOOM-COMMAND-RECONSTRUCTION frame='||
    expected_sha||' bytes='||dbms_lob.getlength(commands));
  status:=doom_mocha_dispose;
  dbms_lob.freetemporary(commands);
end;
/
