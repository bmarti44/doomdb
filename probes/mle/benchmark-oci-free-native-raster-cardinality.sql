whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pagesize 0
set serveroutput on size unlimited linesize 32767 trimspool on

declare
  c_samples constant pls_integer := 30;
  c_batch constant pls_integer := 5;
  type number_list is table of number index by pls_integer;
  type raw_list is table of raw(32767) index by pls_integer;
  l_wall number_list;
  l_clock number_list;

  function elapsed_ms(p_value interval day to second) return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;

  procedure sort_values(p_values in out nocopy number_list) is
    l_value number;l_index pls_integer;
  begin
    for i in 2..c_samples loop
      l_value:=p_values(i);l_index:=i-1;
      while l_index>=1 and p_values(l_index)>l_value loop
        p_values(l_index+1):=p_values(l_index);l_index:=l_index-1;
      end loop;
      p_values(l_index+1):=l_value;
    end loop;
  end;

  procedure run_cell(
    p_name varchar2,
    p_mode pls_integer,
    p_groups pls_integer,
    p_commands pls_integer,
    p_pixels pls_integer
  ) is
    l_source raw_list;l_map raw_list;l_mapped raw_list;
    l_from raw(256):=utl_raw.xrange(hextoraw('00'),hextoraw('ff'));
    l_zero raw(32000):=utl_raw.copies(hextoraw('00'),32000);
    l_chunk0 raw(32767);l_chunk1 raw(32767);l_piece raw(32767);
    l_group_length pls_integer:=ceil(p_pixels/p_groups);
    l_command_base pls_integer:=floor(p_pixels/p_commands);
    l_remainder pls_integer:=mod(p_pixels,p_commands);
    l_length pls_integer;l_group pls_integer;l_source_at pls_integer;
    l_target_at pls_integer;l_checksum number:=0;
    l_wall_started timestamp;l_clock_started number;
    l_wall_values number_list;l_clock_values number_list;
    l_wall_sorted number_list;l_clock_sorted number_list;
    l_clock_suspects pls_integer:=0;
  begin
    for group_ in 1..p_groups loop
      l_source(group_):=utl_raw.copies(
        hextoraw(to_char(mod(group_*37,256),'FM0X')),l_group_length);
      l_map(group_):=utl_raw.bit_xor(l_from,utl_raw.copies(
        hextoraw(to_char(mod(group_*11,256),'FM0X')),256));
      l_mapped(group_):=utl_raw.transliterate(
        l_source(group_),l_map(group_),l_from,hextoraw('00'));
    end loop;
    for warmup_ in 1..5 loop
      if p_mode in(1,3) then
        for group_ in 1..p_groups loop
          l_mapped(group_):=utl_raw.transliterate(
            l_source(group_),l_map(group_),l_from,hextoraw('00'));
        end loop;
      end if;
      if p_mode in(2,3) then
        l_chunk0:=l_zero;l_chunk1:=l_zero;
        for command_ in 1..p_commands loop
          l_length:=l_command_base+
            case when command_<=l_remainder then 1 else 0 end;
          l_group:=mod(command_-1,p_groups)+1;
          l_source_at:=mod((command_-1)*97,
            greatest(1,l_group_length-l_length+1))+1;
          l_piece:=utl_raw.substr(
            l_mapped(l_group),l_length,l_source_at);
          l_target_at:=mod((command_-1)*131,32000-l_length+1)+1;
          if mod(command_,2)=0 then
            l_chunk0:=utl_raw.overlay(
              l_piece,l_chunk0,l_target_at,l_length);
          else
            l_chunk1:=utl_raw.overlay(
              l_piece,l_chunk1,l_target_at,l_length);
          end if;
        end loop;
      end if;
    end loop;
    for sample_ in 1..c_samples loop
      l_wall_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
      for repetition_ in 1..c_batch loop
        if p_mode in(1,3) then
          for group_ in 1..p_groups loop
            l_mapped(group_):=utl_raw.transliterate(
              l_source(group_),l_map(group_),l_from,hextoraw('00'));
          end loop;
        end if;
        if p_mode in(2,3) then
          l_chunk0:=l_zero;l_chunk1:=l_zero;
          for command_ in 1..p_commands loop
            l_length:=l_command_base+
              case when command_<=l_remainder then 1 else 0 end;
            l_group:=mod(command_-1,p_groups)+1;
            l_source_at:=mod((command_-1)*97,
              greatest(1,l_group_length-l_length+1))+1;
            l_piece:=utl_raw.substr(
              l_mapped(l_group),l_length,l_source_at);
            l_target_at:=mod((command_-1)*131,32000-l_length+1)+1;
            if mod(command_,2)=0 then
              l_chunk0:=utl_raw.overlay(
                l_piece,l_chunk0,l_target_at,l_length);
            else
              l_chunk1:=utl_raw.overlay(
                l_piece,l_chunk1,l_target_at,l_length);
            end if;
          end loop;
          l_checksum:=l_checksum+utl_raw.length(l_chunk0)+
            utl_raw.length(l_chunk1);
        else
          l_checksum:=l_checksum+utl_raw.length(l_mapped(p_groups));
        end if;
      end loop;
      l_wall_values(sample_):=elapsed_ms(systimestamp-l_wall_started)/c_batch;
      l_clock_values(sample_):=
        (dbms_utility.get_time-l_clock_started)*10/c_batch;
      if abs(l_wall_values(sample_)-l_clock_values(sample_))>30 then
        l_clock_suspects:=l_clock_suspects+1;
      end if;
    end loop;
    l_wall_sorted:=l_wall_values;l_clock_sorted:=l_clock_values;
    sort_values(l_wall_sorted);sort_values(l_clock_sorted);
    dbms_output.put_line(
      'PMLE_FREE_NATIVE_CARDINALITY|PASS|cell='||p_name||
      '|groups='||p_groups||'|commands='||p_commands||
      '|pixels='||p_pixels||'|samples='||c_samples||
      '|batch='||c_batch||
      '|wall_p50_ms='||to_char(l_wall_sorted(15),'FM999999990D000')||
      '|wall_p95_ms='||to_char(l_wall_sorted(29),'FM999999990D000')||
      '|clock_p50_ms='||to_char(l_clock_sorted(15),'FM999999990D000')||
      '|clock_p95_ms='||to_char(l_clock_sorted(29),'FM999999990D000')||
      '|clock_suspects='||l_clock_suspects||
      '|checksum='||l_checksum);
  end;
begin
  -- The cardinalities come from the exact 5,250-tic accepted command stream:
  -- average 17 LUTs / 1,505 commands / 56,615 drawn pixels;
  -- peak 29 LUTs / 2,325 commands / 77,869 drawn pixels.
  run_cell('translate_average',1,17,1505,56615);
  run_cell('scatter_average',2,17,1505,56615);
  run_cell('combined_average',3,17,1505,56615);
  run_cell('translate_peak',1,29,2325,77869);
  run_cell('scatter_peak',2,29,2325,77869);
  run_cell('combined_peak',3,29,2325,77869);
end;
/
