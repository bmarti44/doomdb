whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ constant varchar2(32):='0123456789abcdef0123456789abcdef';
  result_ varchar2(4000);
  expected_angle binary_double:=0d;
  actual_angle binary_double;
  delimiter_ pls_integer;
  failures_ pls_integer:=0;
  command_pack raw(32767);
  delta_pack raw(32767);
  batch_expected binary_double:=0d;
  batch_actual binary_double;
begin
  result_:=doom_resident_sim_load_player(session_,0,0,0d,0d,0d,0d);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;

  -- 270 unique SQL-oracle turns exercise both wrap directions and no-op turns.
  for seq_ in 1..270 loop
    declare
      turn_ pls_integer:=case mod(seq_,3) when 0 then -1 when 1 then 1 else 0 end;
    begin
      expected_angle:=mod(expected_angle+turn_*5.625d+360d,360d);
      result_:=doom_resident_sim_step_turn(session_,seq_,turn_);
      if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
      actual_angle:=to_binary_double(regexp_substr(result_,'[^|]+',1,4));
      if actual_angle<>expected_angle then
        failures_:=failures_+1;
        dbms_output.put_line('scalar mismatch seq='||seq_||' expected='||
          expected_angle||' actual='||actual_angle);
      end if;
    end;
  end loop;
  if failures_<>0 then raise_application_error(-20000,'scalar parity failures='||failures_);end if;

  -- Reset and prove the production-shaped four-command packed boundary. Each
  -- record is int64 sequence, int8 turn, and seven reserved zero bytes.
  result_:=doom_resident_sim_load_player(session_,0,0,0d,0d,0d,0d);
  command_pack:=hextoraw('444d534301040000' ||
    '00000000000000010100000000000000' ||
    '00000000000000020100000000000000' ||
    '0000000000000003ff00000000000000' ||
    '00000000000000040000000000000000');
  delta_pack:=doom_resident_sim_step_turn_batch(session_,command_pack);
  if rawtohex(utl_raw.substr(delta_pack,1,8))<>'444D534401000400' then
    raise_application_error(-20000,'delta header mismatch '||rawtohex(delta_pack));
  end if;
  for index_ in 0..3 loop
    batch_expected:=mod(batch_expected+
      case index_ when 0 then 1 when 1 then 1 when 2 then -1 else 0 end*5.625d+360d,360d);
    batch_actual:=utl_raw.cast_to_binary_double(
      utl_raw.substr(delta_pack,8+index_*24+17,8),utl_raw.big_endian);
    if batch_actual<>batch_expected then
      raise_application_error(-20000,'batch parity index='||index_);
    end if;
  end loop;

  -- A rejected pack must not partially mutate the retained state.
  result_:=doom_resident_sim_state(session_);
  delta_pack:=doom_resident_sim_step_turn_batch(session_,
    hextoraw('444d534301020000' ||
      '00000000000000050100000000000000' ||
      '00000000000000070300000000000000'));
  if rawtohex(utl_raw.substr(delta_pack,6,1))<>'01' then
    raise_application_error(-20000,'invalid pack unexpectedly accepted');
  end if;
  if doom_resident_sim_state(session_)<>result_ then
    raise_application_error(-20000,'rejected batch mutated state');
  end if;

  dbms_output.put_line('resident_sim_turn_parity=270/270');
  dbms_output.put_line('resident_sim_batch_parity=4/4');
  dbms_output.put_line('resident_sim_atomic_rejection=PASS');
end;
/
