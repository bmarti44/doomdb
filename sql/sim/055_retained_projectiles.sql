-- Advance pre-existing projectiles in authoritative SQL, then return only the
-- mutations needed to reconcile the retained primitive-array owner.  This is
-- intentionally one packed boundary crossing: OJVM must never row-walk the
-- relational world on the warm path.
create or replace package doom_retained_projectiles authid definer as
  procedure advance_and_pack(
    p_session_token in varchar2,
    p_tic in number,
    p_pack out raw
  );
end doom_retained_projectiles;
/

create or replace package body doom_retained_projectiles as
  procedure advance_and_pack(
    p_session_token in varchar2,
    p_tic in number,
    p_pack out raw
  ) is
    l_damage_count pls_integer;
    l_projectile_count pls_integer;
    l_total pls_integer;l_java_count pls_integer;l_java_owner pls_integer:=0;
    l_player_health number;l_player_armor number;l_player_alive number;
    l_next_mobj number;l_next_event number;
    l_lineage varchar2(64);
    procedure append_raw(p_value raw) is
    begin
      if p_value is not null then p_pack:=utl_raw.concat(p_pack,p_value);end if;
    end;
    procedure append_i32(p_value number) is
    begin
      append_raw(utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));
    end;
    procedure append_u16(p_value number) is
    begin
      if p_value<0 or p_value>65535 or p_value<>trunc(p_value) then
        raise_application_error(-20731,'retained projectile pack count');
      end if;
      append_raw(utl_raw.substr(
        utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian),3,2));
    end;
    procedure append_number(p_value number) is
      l_raw raw(22):=utl_raw.cast_from_number(p_value);
    begin
      append_raw(utl_raw.concat(
        utl_raw.substr(utl_raw.cast_from_binary_integer(utl_raw.length(l_raw),
          utl_raw.big_endian),4,1),
        utl_raw.substr(utl_raw.concat(l_raw,
          hextoraw('00000000000000000000000000000000000000000000')),1,22)));
    end;
  begin
    select save_lineage into l_lineage from game_sessions
      where session_token=p_session_token;
    select count(*),coalesce(sum(case when owner.mobj_id is not null
      and td.category='monster' and d.splash_radius=0
      and 1=(select count(*) from mobjs sibling
        where sibling.session_token=p.session_token
          and sibling.projectile_kind is not null
          and sibling.owner_mobj_id=p.owner_mobj_id)
      then 1 else 0 end),0)
      into l_total,l_java_count
    from mobjs p join doom_projectile_def d on d.projectile_kind=p.projectile_kind
    left join mobjs owner on owner.session_token=p.session_token
      and owner.mobj_id=p.owner_mobj_id and owner.health>0
    left join doom_thing_type_def td on td.thing_type=owner.thing_type
    where p.session_token=p_session_token and p.projectile_kind is not null;
    if l_total=l_java_count then l_java_owner:=1;
    else doom_combat.advance_projectiles(p_session_token,p_tic);end if;

    select
      (select count(*) from (select distinct target_mobj_id from game_events
        where session_token=p_session_token and lineage=l_lineage and tic=p_tic
          and event_type in('DAMAGE','BARREL_EXPLODE')
          and target_mobj_id is not null)),
      (select count(*) from mobjs where session_token=p_session_token
        and projectile_kind is not null)
      into l_damage_count,l_projectile_count from dual;
    select p.health,p.armor,p.alive,
      (select coalesce(max(mobj_id),0)+1 from mobjs
        where session_token=p_session_token),
      (select coalesce(max(event_ordinal)+1,0) from game_events
        where session_token=p_session_token and lineage=l_lineage and tic=p_tic)
      into l_player_health,l_player_armor,l_player_alive,l_next_mobj,l_next_event
      from players p join game_sessions s
        on s.session_token=p.session_token and s.current_player_id=p.player_id
      where s.session_token=p_session_token;

    -- DPRJ/v1: fixed 32-byte header, 9-byte damage rows, then 50-byte
    -- projectile rows (id + two canonical fixed-width Oracle NUMBERs).
    p_pack:=case when l_java_owner=1 then hextoraw('4450524A0101')
      else hextoraw('4450524A0100') end;
    append_u16(l_damage_count);append_u16(l_projectile_count);append_u16(0);
    append_i32(l_player_health);append_i32(l_player_armor);append_i32(l_player_alive);
    append_i32(l_next_mobj);append_i32(l_next_event);

    for damaged in (
      select m.mobj_id,m.health,m.exploded
      from mobjs m join (
        select distinct target_mobj_id
        from game_events
        where session_token=p_session_token and lineage=l_lineage and tic=p_tic
          and event_type in('DAMAGE','BARREL_EXPLODE')
          and target_mobj_id is not null
      ) e on e.target_mobj_id=m.mobj_id
      where m.session_token=p_session_token
      order by m.mobj_id
    ) loop
      append_i32(damaged.mobj_id);append_i32(damaged.health);
      append_raw(case when damaged.exploded=1 then hextoraw('01') else hextoraw('00') end);
    end loop;
    for projectile in (
      select mobj_id,x,y from mobjs
      where session_token=p_session_token and projectile_kind is not null
      order by mobj_id
    ) loop
      append_i32(projectile.mobj_id);append_number(projectile.x);append_number(projectile.y);
    end loop;
    if utl_raw.length(p_pack)<>32+l_damage_count*9+l_projectile_count*50 then
      raise_application_error(-20731,'retained projectile pack length');
    end if;
  end;
end doom_retained_projectiles;
/
