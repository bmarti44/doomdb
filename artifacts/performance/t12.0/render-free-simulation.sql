whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited feedback off timing off

-- Destructive only to the throwaway session created here. Measures the public
-- simulation/history transaction without DOOM_API.RENDER_PAYLOAD.
declare
  type num_tab is table of number index by binary_integer;
  l_ms num_tab;
  l_raw_ms num_tab;
  l_session varchar2(32);
  l_payload blob;
  l_cmd clob;
  l_t0 timestamp;
  l_n constant pls_integer := 270;
  l_tmp number;
  function elapsed_ms(p_start timestamp) return number is
    x interval day to second := systimestamp-p_start;
  begin
    return extract(day from x)*86400000+extract(hour from x)*3600000+
      extract(minute from x)*60000+extract(second from x)*1000;
  end;
  function command_doc(p_seq number) return clob is
  begin
    return to_clob('{"v":1,"commands":[{"turn":'||
      case when mod(p_seq,2)=0 then '1' else '-1' end||
      ',"forward":0,"strafe":0,"run":0,"fire":0,"use":0,'||
      '"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":'||
      p_seq||'}]}');
  end;
begin
  doom_api.new_game(3,l_session,l_payload);
  for i in 1..30 loop
    doom_tic_tx.apply_batch(l_session,command_doc(i),l_payload);
    commit;
  end loop;
  for i in 1..l_n loop
    l_cmd:=command_doc(i+30);
    l_t0:=systimestamp;
    doom_tic_tx.apply_batch(l_session,l_cmd,l_payload);
    commit;
    l_ms(i):=elapsed_ms(l_t0);
    l_raw_ms(i):=l_ms(i);
  end loop;
  for i in 1..l_n-1 loop
    for j in i+1..l_n loop
      if l_ms(j)<l_ms(i) then
        l_tmp:=l_ms(i); l_ms(i):=l_ms(j); l_ms(j):=l_tmp;
      end if;
    end loop;
  end loop;
  dbms_output.put_line('SIM_SAMPLES='||l_n);
  dbms_output.put_line('SIM_P50_MS='||to_char(l_ms(ceil(l_n*.50)),'FM9999990.000'));
  dbms_output.put_line('SIM_P95_MS='||to_char(l_ms(ceil(l_n*.95)),'FM9999990.000'));
  dbms_output.put_line('SIM_P99_MS='||to_char(l_ms(ceil(l_n*.99)),'FM9999990.000'));
  dbms_output.put_line('SIM_MAX_MS='||to_char(l_ms(l_n),'FM9999990.000'));
  for i in 1..l_n loop
    if l_raw_ms(i)>=l_ms(ceil(l_n*.95)) then
      dbms_output.put_line('SIM_P95_OUTLIER_SEQ='||(i+30)||
        ' MS='||to_char(l_raw_ms(i),'FM9999990.000'));
    end if;
  end loop;
  delete from game_sessions where session_token=l_session;
  commit;
exception when others then
  rollback;
  if l_session is not null then
    delete from game_sessions where session_token=l_session;
    commit;
  end if;
  raise;
end;
/
