whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  c_passes constant pls_integer:=6;
  c_samples constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  type pass_values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_pass_p95 pass_values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_get_started number;l_wall number;l_get number;l_value number;
  l_checksum number;l_expected number:=1469833290;
  l_suspects number;l_j pls_integer;l_final_worst number;

  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for i in 1..5 loop
    l_checksum:=doom_plain_raster_frame(1);
    if l_checksum<>l_expected then
      raise_application_error(-20796,'plain raster warmup checksum mismatch');
    end if;
  end loop;
  if doom_plain_raster_footprint<>129792 then
    raise_application_error(-20796,'plain raster footprint mismatch');
  end if;

  for pass in 1..c_passes loop
    l_suspects:=0;l_get_started:=dbms_utility.get_time;
    l_pass_started:=systimestamp;
    for sample in 1..c_samples loop
      l_started:=systimestamp;
      l_checksum:=doom_plain_raster_frame(1);
      l_values(sample):=elapsed_ms(systimestamp-l_started);
      l_sorted(sample):=l_values(sample);
      if l_checksum<>l_expected then
        raise_application_error(-20796,'plain raster checksum mismatch');
      end if;
    end loop;
    l_wall:=elapsed_ms(systimestamp-l_pass_started);
    l_get:=(dbms_utility.get_time-l_get_started)*10;
    if abs(l_wall-l_get)>30 then l_suspects:=1;end if;
    for i in 2..c_samples loop
      l_value:=l_sorted(i);l_j:=i-1;
      while l_j>=1 and l_sorted(l_j)>l_value loop
        l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
      end loop;
      l_sorted(l_j+1):=l_value;
    end loop;
    l_pass_p95(pass):=l_sorted(ceil(c_samples*.95));
    dbms_output.put_line(
      'PMLE_PLAIN_RASTER_PASS|pass='||pass||'|frames='||c_samples||
      '|p50_ms='||round(l_sorted(ceil(c_samples*.50)),3)||
      '|p95_ms='||round(l_pass_p95(pass),3)||
      '|wall_ms='||round(l_wall,3)||
      '|throughput_fps='||round(c_samples*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||'|checksum='||l_checksum);
  end loop;
  l_final_worst:=greatest(l_pass_p95(c_passes-1),l_pass_p95(c_passes));
  dbms_output.put_line(
    'PMLE_PLAIN_RASTER_VERDICT|'||
    case
      when l_final_worst<=5 then 'COMPILED_RASTER_SHAPE_PROMISING'
      when l_final_worst<=10 then 'COMPILED_RASTER_SHAPE_AMBIGUOUS'
      else 'COMPILED_RASTER_SHAPE_INSUFFICIENT'
    end||
    '|final_two_worst_p95_ms='||round(l_final_worst,3)||
    '|first_p95_ms='||round(l_pass_p95(1),3)||
    '|passes='||c_passes||'|frames_per_pass='||c_samples||
    '|settings=PRODUCTION_DEFAULT|classification=DIAGNOSTIC_NOT_GATE');
  doom_plain_raster_release;
exception when others then
  begin doom_plain_raster_release;exception when others then null;end;
  raise;
end;
/
