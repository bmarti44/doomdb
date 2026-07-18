whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_frame blob;
  l_status varchar2(4000);

  procedure assert_contains(p_actual varchar2,p_expected varchar2) is
  begin
    if instr(p_actual,p_expected)=0 then
      raise_application_error(-20000,
        'expected '||p_expected||' in '||substr(p_actual,1,1000));
    end if;
  end;
begin
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  l_status:=doom_mocha_new_game(2,1,1);
  assert_contains(l_status,'ok|state=new-game');

  -- Vanilla holds keyboard turns at 320 for the first five tics.
  for l_tic in 1..5 loop
    l_status:=doom_mocha_step_controls_frame(
      1,1,0,0,1,0,0,0,0,0,l_frame);
    assert_contains(l_status,'commandHex=1900fec000000001');
    assert_contains(l_status,'turnHeld='||l_tic);
    if dbms_lob.getlength(l_frame)<>64000 then
      raise_application_error(-20000,'indexed frame length mismatch');
    end if;
  end loop;

  -- The sixth held tic reaches the normal/run turn rate. Weapon slot 3 maps
  -- to vanilla zero-based weapon bits while fire and use remain combinable.
  l_status:=doom_mocha_step_controls_frame(1,1,1,1,1,1,3,0,0,0,l_frame);
  assert_contains(l_status,'commandHex=3228fb0000000017');
  assert_contains(l_status,'turnHeld=6');

  -- Releasing turn resets acceleration; negative axes retain signed bytes.
  l_status:=doom_mocha_step_controls_frame(0,-1,-1,0,0,0,0,0,0,0,l_frame);
  assert_contains(l_status,'commandHex=e7e8000000000000');
  assert_contains(l_status,'turnHeld=0');

  dbms_output.put_line(
    'PASS MOCHADOOM-CONTROL-CODEC tics=7 frameBytes='||
    dbms_lob.getlength(l_frame));
  dbms_lob.freetemporary(l_frame);
end;
/
