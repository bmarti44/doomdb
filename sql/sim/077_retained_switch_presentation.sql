-- Complete, ordered SQL-oracle image for retained renderer switch presentation.
-- DMSV/v1 is appended after the DMWG/v3 mobj rows.  Its complete-image flag
-- makes button reset deterministic: a zero row actively clears retained state.
create or replace package doom_retained_switch_presentation authid definer as
  procedure build(p_session_token in varchar2,p_pack out raw);
end doom_retained_switch_presentation;
/

create or replace package body doom_retained_switch_presentation as
  procedure fail(p_message varchar2) is
  begin raise_application_error(-20848,'DMSV/v1: '||p_message);end;

  procedure append_raw(p_pack in out nocopy raw,p_value raw) is
  begin
    if p_value is not null then p_pack:=utl_raw.concat(p_pack,p_value);end if;
    if utl_raw.length(p_pack)>32767 then fail('RAW limit');end if;
  end;

  procedure append_u8(p_pack in out nocopy raw,p_value pls_integer) is
  begin
    if p_value<0 or p_value>255 then fail('u8');end if;
    append_raw(p_pack,utl_raw.substr(
      utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian),4,1));
  end;

  procedure append_u16(p_pack in out nocopy raw,p_value pls_integer) is
  begin
    if p_value<0 or p_value>65535 then fail('u16');end if;
    append_raw(p_pack,utl_raw.substr(
      utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian),3,2));
  end;

  procedure append_i32(p_pack in out nocopy raw,p_value pls_integer) is
  begin append_raw(p_pack,utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));end;

  procedure build(p_session_token in varchar2,p_pack out raw) is
    l_count pls_integer;l_name_raw raw(32);l_name varchar2(32);
  begin
    select count(*) into l_count
      from line_state ls join doom_map_linedef ml on ml.linedef_id=ls.linedef_id
      join doom_map_sidedef sd on sd.sidedef_id=ml.right_sidedef_id
     where ls.session_token=p_session_token and
       coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                nullif(sd.lower_texture,'-'),'NONE') like 'SW1%';
    if l_count=0 or l_count>65535 then fail('switch line count');end if;
    -- magic, version, complete-image flag, row count
    p_pack:=hextoraw('444D53560101');append_u16(p_pack,l_count);
    for r in (
      select ls.linedef_id,ls.switch_on,
             case when ls.switch_on=1 then sw.timer_tics else -1 end timer_tics,
             coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                      nullif(sd.lower_texture,'-'),'NONE') restore_texture
        from line_state ls
        join doom_map_linedef ml on ml.linedef_id=ls.linedef_id
        join doom_map_sidedef sd on sd.sidedef_id=ml.right_sidedef_id
        left join active_switches sw on sw.session_token=ls.session_token
          and sw.linedef_id=ls.linedef_id
       where ls.session_token=p_session_token
         and coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                      nullif(sd.lower_texture,'-'),'NONE') like 'SW1%'
       order by ls.linedef_id
    ) loop
      if (r.switch_on=1 and r.timer_tics is null) or
         (r.switch_on=0 and r.timer_tics<>-1) then fail('timer/state mismatch');end if;
      l_name:=r.restore_texture;l_name_raw:=utl_i18n.string_to_raw(l_name,'AL32UTF8');
      if utl_raw.length(l_name_raw)>32 then fail('texture length');end if;
      append_i32(p_pack,r.linedef_id);append_u8(p_pack,r.switch_on);
      append_i32(p_pack,r.timer_tics);append_u8(p_pack,utl_raw.length(l_name_raw));
      append_raw(p_pack,l_name_raw);
    end loop;
  exception when no_data_found then fail('missing immutable sidedef');
  end;
end doom_retained_switch_presentation;
/
