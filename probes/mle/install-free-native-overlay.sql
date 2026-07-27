whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

begin
  execute immediate 'drop package doom_free_native_overlay';
exception when others then
  if sqlcode<>-4043 then raise;end if;
end;
/

create package doom_free_native_overlay authid definer as
  procedure begin_frame;
  procedure consume_records(p_records raw);
  procedure finish_frame(
    p_frame0 out raw,
    p_frame1 out raw,
    p_commands out number,
    p_misses out number);
  procedure reset_cache;
end;
/

create package body doom_free_native_overlay as
  type cache_t is table of raw(200) index by binary_integer;
  g_cache cache_t;
  g_frame0 raw(32000);
  g_frame1 raw(32000);
  g_commands pls_integer;
  g_misses pls_integer;
  g_background raw(32000);

  function byte_at(p_value raw,p_position pls_integer)
    return pls_integer is
  begin
    return to_number(
      '0'||rawtohex(utl_raw.substr(p_value,p_position,1)),'XXX');
  end;

  function big_u16(p_value raw,p_position pls_integer)
    return pls_integer is
  begin
    return to_number(
      '0'||rawtohex(utl_raw.substr(p_value,p_position,2)),'XXXXX');
  end;

  function big_u32(p_value raw,p_position pls_integer)
    return pls_integer is
  begin
    return to_number(
      '0'||rawtohex(utl_raw.substr(p_value,p_position,4)),'XXXXXXXXX');
  end;

  procedure begin_frame is
  begin
    if g_background is null then
      g_background:=utl_raw.copies(utl_raw.concat(
        utl_raw.copies(hextoraw('60'),100),
        utl_raw.copies(hextoraw('30'),100)),160);
    end if;
    g_frame0:=g_background;
    g_frame1:=g_background;
    g_commands:=0;
    g_misses:=0;
  end;

  procedure consume_records(p_records raw) is
    l_at pls_integer:=1;
    l_bytes pls_integer:=utl_raw.length(p_records);
    l_slot pls_integer;
    l_target pls_integer;
    l_length pls_integer;
    l_miss pls_integer;
    l_segment raw(200);
  begin
    if g_frame0 is null then
      raise_application_error(-20796,'native overlay frame is not open');
    end if;
    while l_at<=l_bytes loop
      if l_at+7>l_bytes then
        raise_application_error(-20796,'truncated native overlay record');
      end if;
      l_slot:=big_u32(p_records,l_at);
      l_target:=big_u16(p_records,l_at+4);
      l_length:=byte_at(p_records,l_at+6);
      l_miss:=byte_at(p_records,l_at+7);
      l_at:=l_at+8;
      if l_slot<0 or l_slot>=262144
          or l_target<0 or l_target+l_length>64000
          or l_length<1 or l_length>200
          or l_miss not in(0,1) then
        raise_application_error(-20796,'invalid native overlay record');
      end if;
      if l_miss=1 then
        if l_at+l_length-1>l_bytes then
          raise_application_error(-20796,'truncated native overlay payload');
        end if;
        l_segment:=utl_raw.substr(p_records,l_at,l_length);
        l_at:=l_at+l_length;
        g_cache(l_slot):=l_segment;
        g_misses:=g_misses+1;
      else
        if not g_cache.exists(l_slot) then
          raise_application_error(-20796,'native overlay cache desync');
        end if;
        l_segment:=g_cache(l_slot);
        if utl_raw.length(l_segment)<>l_length then
          raise_application_error(-20796,'native overlay cache length mismatch');
        end if;
      end if;
      if l_target<32000 then
        if l_target+l_length>32000 then
          raise_application_error(-20796,'native overlay crosses frame half');
        end if;
        g_frame0:=utl_raw.overlay(
          l_segment,g_frame0,l_target+1,l_length);
      else
        g_frame1:=utl_raw.overlay(
          l_segment,g_frame1,l_target-32000+1,l_length);
      end if;
      g_commands:=g_commands+1;
    end loop;
  end;

  procedure finish_frame(
    p_frame0 out raw,
    p_frame1 out raw,
    p_commands out number,
    p_misses out number) is
  begin
    if g_frame0 is null or utl_raw.length(g_frame0)<>32000
        or utl_raw.length(g_frame1)<>32000 then
      raise_application_error(-20796,'native overlay frame is incomplete');
    end if;
    p_frame0:=g_frame0;
    p_frame1:=g_frame1;
    p_commands:=g_commands;
    p_misses:=g_misses;
    g_frame0:=null;
    g_frame1:=null;
  end;

  procedure reset_cache is
  begin
    g_cache.delete;
    g_frame0:=null;
    g_frame1:=null;
    g_commands:=0;
    g_misses:=0;
  end;
end;
/

begin
  doom_free_native_overlay.reset_cache;
  dbms_output.put_line(
    'PMLE_FREE_NATIVE_OVERLAY_INSTALL|PASS|cache_slots=262144|frame_halves=2');
end;
/
