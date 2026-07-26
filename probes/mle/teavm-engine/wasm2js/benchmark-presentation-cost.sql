whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  c_linear_samples constant pls_integer:=20;
  c_linear_frames constant pls_integer:=1;
  c_js_samples constant pls_integer:=5;
  c_render_p95_budget constant number:=2.531;
  type values_t is table of number index by pls_integer;
  l_linear values_t;l_js values_t;l_linear_sorted values_t;l_js_sorted values_t;
  l_started timestamp with time zone;l_elapsed number;l_value number;
  l_get_started number;l_get_elapsed number;
  l_linear_checksum number;l_js_checksum number;
  l_linear_suspect number:=0;l_js_suspect number:=0;
  l_before varchar2(200);l_after varchar2(200);

  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;

  procedure sort_values(
      p_values in out nocopy values_t,p_count pls_integer) is
    l_sort number;l_index pls_integer;
  begin
    for i in 2..p_count loop
      l_sort:=p_values(i);l_index:=i-1;
      while l_index>=1 and p_values(l_index)>l_sort loop
        p_values(l_index+1):=p_values(l_index);l_index:=l_index-1;
      end loop;
      p_values(l_index+1):=l_sort;
    end loop;
  end;
begin
  l_before:=doom_wasm2js_cost_memory;
  for i in 1..5 loop
    l_linear_checksum:=doom_wasm2js_cost_linear(c_linear_frames);
  end loop;
  if doom_wasm2js_cost_linear(1)<>doom_wasm2js_cost_js(1) then
    raise_application_error(-20796,'presentation-cost one-frame mismatch');
  end if;

  for i in 1..c_linear_samples loop
    l_get_started:=dbms_utility.get_time;l_started:=systimestamp;
    l_linear_checksum:=doom_wasm2js_cost_linear(c_linear_frames);
    l_elapsed:=elapsed_ms(systimestamp-l_started);
    l_get_elapsed:=(dbms_utility.get_time-l_get_started)*10;
    l_linear(i):=l_elapsed/c_linear_frames;
    l_linear_sorted(i):=l_linear(i);
    if abs(l_elapsed-l_get_elapsed)>30 then
      l_linear_suspect:=l_linear_suspect+1;
    end if;
  end loop;
  sort_values(l_linear_sorted,c_linear_samples);
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_ARM|arm=WASM2JS_LINEAR|frames='||
    (c_linear_samples*c_linear_frames)||'|p50_ms='||
    round(l_linear_sorted(ceil(c_linear_samples*.50)),3)||'|p95_ms='||
    round(l_linear_sorted(ceil(c_linear_samples*.95)),3)||
    '|suspect_samples='||l_linear_suspect||
    '|checksum='||l_linear_checksum);

  for i in 1..3 loop l_js_checksum:=doom_wasm2js_cost_js(1);end loop;
  for i in 1..c_js_samples loop
    l_get_started:=dbms_utility.get_time;l_started:=systimestamp;
    l_js_checksum:=doom_wasm2js_cost_js(1);
    l_elapsed:=elapsed_ms(systimestamp-l_started);
    l_get_elapsed:=(dbms_utility.get_time-l_get_started)*10;
    l_js(i):=l_elapsed;l_js_sorted(i):=l_elapsed;
    if abs(l_elapsed-l_get_elapsed)>30 then
      l_js_suspect:=l_js_suspect+1;
    end if;
  end loop;
  sort_values(l_js_sorted,c_js_samples);
  l_after:=doom_wasm2js_cost_memory;
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_ARM|arm=PURE_MLE_JS|frames='||c_js_samples||
    '|p50_ms='||round(l_js_sorted(ceil(c_js_samples*.50)),3)||
    '|p95_ms='||round(l_js_sorted(ceil(c_js_samples*.95)),3)||
    '|suspect_samples='||l_js_suspect||'|checksum='||l_js_checksum);

  dbms_output.put_line(
    'PMLE_WASM2JS_COST_VERDICT|'||
    case
      when l_linear_sorted(ceil(c_linear_samples*.95))<=c_render_p95_budget
        then 'UNIFIED_LIVE_COST_ELIGIBLE_FOR_PARITY_WORK'
      when l_linear_sorted(ceil(c_linear_samples*.95))<28.571
        then 'SPLIT_RENDER_COST_ELIGIBLE_FOR_PARITY_WORK'
      else 'DVR_ONLY_ON_COST'
    end||
    '|p95_ms='||
    round(l_linear_sorted(ceil(c_linear_samples*.95)),3)||
    '|budget_ms='||c_render_p95_budget||
    '|structural_speedup='||
    round(l_js_sorted(ceil(c_js_samples*.95))/
      l_linear_sorted(ceil(c_linear_samples*.95)),3)||
    '|memory_before='||l_before||'|memory_after='||l_after||
    '|classification=DIAGNOSTIC_NOT_GATE|tier=PRESENTATION_DIAGNOSTIC_ONLY');
  doom_wasm2js_cost_release;
exception when others then
  begin doom_wasm2js_cost_release;exception when others then null;end;
  raise;
end;
/
