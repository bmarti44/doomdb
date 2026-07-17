-- T6.3 relational world machines. The package runs inside the owning tic
-- transaction and all durable machine state is declared by the base schema.

merge into doom_config d
using (
  select 'WORLD_USE_RANGE' config_key,64 number_value from dual union all
  select 'WORLD_BUTTON_TICS',35 from dual union all
  select 'WORLD_DOOR_SPEED',2 from dual union all
  select 'WORLD_BLAZE_SPEED',8 from dual union all
  select 'WORLD_DOOR_WAIT',150 from dual union all
  select 'WORLD_LIFT_SPEED',1 from dual union all
  select 'WORLD_LIFT_WAIT',105 from dual union all
  select 'WORLD_DAMAGE_PERIOD',32 from dual union all
  select 'WORLD_DAMAGE_AMOUNT',5 from dual union all
  select 'WORLD_STROBE_BRIGHT',5 from dual union all
  select 'WORLD_STROBE_DARK',35 from dual
) s on(d.config_key=s.config_key)
when matched then update set d.number_value=s.number_value,d.text_value=null
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,null);

create or replace package doom_world_machines authid definer as
  function requires_advance(
    p_session in varchar2,
    p_previous_x in number,p_previous_y in number,
    p_current_x in number,p_current_y in number,p_current_sector in number,
    p_use_action in number
  ) return number;
  procedure advance(
    p_session in varchar2,
    p_tic in number,
    p_previous_x in number,
    p_previous_y in number,
    p_use_action in number default null
  );
end doom_world_machines;
/

create or replace package body doom_world_machines as
  procedure emit_event(
    p_session varchar2,p_tic number,p_type varchar2,
    p_number number default null,p_text varchar2 default null
  ) is
    l_ordinal number;
  begin
    select coalesce(max(event_ordinal)+1,0) into l_ordinal
      from game_events where session_token=p_session and
        lineage=(select save_lineage from game_sessions where session_token=p_session)
        and tic=p_tic;
    insert into game_events(session_token,tic,event_ordinal,event_type,number_value,text_value)
      values(p_session,p_tic,l_ordinal,p_type,p_number,p_text);
  end;

  function config_number(p_key varchar2) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  end;

  function requires_advance(
    p_session in varchar2,
    p_previous_x in number,p_previous_y in number,
    p_current_x in number,p_current_y in number,p_current_sector in number,
    p_use_action in number
  ) return number is
    l_count number;
  begin
    if p_use_action=1 then return 1;end if;
    select count(*) into l_count from (
      select 1 from active_movers where session_token=p_session
      union all select 1 from active_switches where session_token=p_session);
    if l_count>0 then return 1;end if;
    select count(*) into l_count from doom_map_sector
      where sector_id=p_current_sector and special in(7,9);
    if l_count>0 then return 1;end if;
    if p_current_x=p_previous_x and p_current_y=p_previous_y then return 0;end if;
    select count(*) into l_count from (
      select 1 from (
        select
          ((v2.x-v1.x)*(p_previous_y-v1.y)-(v2.y-v1.y)*(p_previous_x-v1.x)) prior_side,
          ((v2.x-v1.x)*(p_current_y-v1.y)-(v2.y-v1.y)*(p_current_x-v1.x)) current_side,
          ((v1.x-p_previous_x)*(p_current_y-p_previous_y)-
            (v1.y-p_previous_y)*(p_current_x-p_previous_x)) /
            nullif((p_current_x-p_previous_x)*(v2.y-v1.y)-
              (p_current_y-p_previous_y)*(v2.x-v1.x),0) segment_t,
          ((v1.x-p_previous_x)*(v2.y-v1.y)-(v1.y-p_previous_y)*(v2.x-v1.x)) /
            nullif((p_current_x-p_previous_x)*(v2.y-v1.y)-
              (p_current_y-p_previous_y)*(v2.x-v1.x),0) cross_t
        from doom_map_linedef ml join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
          join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
          join doom_linedef_special_def d on d.special_id=ml.special
        where instr(d.semantics,'WALK|')=1
      ) where prior_side<0 and current_side>0 and cross_t>0 and cross_t<1
          and segment_t>0 and segment_t<1 and rownum=1);
    return case when l_count>0 then 1 else 0 end;
  end;

  function occupant_in_sector(p_session varchar2,x_sector number) return boolean is
    l_count number;
  begin
    select count(*) into l_count
    from (
      select p.x,p.y from game_sessions g join players p
        on p.session_token=g.session_token and p.player_id=g.current_player_id
       where g.session_token=p_session and p.alive=1
      union all
      select m.x,m.y from mobjs m where m.session_token=p_session and m.health>0
    ) o
    where exists(select 1 from table(doom_bsp_locate(o.x,o.y)) b
                  where b.sector_id=x_sector);
    return l_count>0;
  end;

  function neighbor_floor(x_sector number,p_fallback number) return number is
    l_value number;
  begin
    select coalesce(min(other_floor),p_fallback) into l_value
    from (
      select case when rs.sector_id=x_sector then lsec.floor_height
                  else rsec.floor_height end other_floor
      from doom_map_linedef l
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join doom_map_sector rsec on rsec.sector_id=rs.sector_id
      join doom_map_sector lsec on lsec.sector_id=ls.sector_id
      where rs.sector_id=x_sector or ls.sector_id=x_sector
    );
    return l_value;
  end;

  function door_top(x_sector number,p_fallback number) return number is
    l_value number;
  begin
    select coalesce(min(other_ceiling)-4,p_fallback) into l_value
    from (
      select case when rs.sector_id=x_sector then lsec.ceiling_height
                  else rsec.ceiling_height end other_ceiling
      from doom_map_linedef l
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join doom_map_sector rsec on rsec.sector_id=rs.sector_id
      join doom_map_sector lsec on lsec.sector_id=ls.sector_id
      where rs.sector_id=x_sector or ls.sector_id=x_sector
    );
    return greatest(l_value,p_fallback);
  end;

  procedure add_mover(
    p_session varchar2,x_sector number,p_plane varchar2,p_kind varchar2,
    p_direction number,p_speed number,p_target number,p_origin number,
    p_wait number,p_line number
  ) is
    l_id number;
  begin
    select coalesce(max(mover_id)+1,0) into l_id from active_movers
      where session_token=p_session;
    insert into active_movers(session_token,mover_id,sector_id,plane,direction,
      speed,target_height,wait_tics,timer_tics,mover_kind,origin_height,
      source_linedef_id)
    select p_session,l_id,x_sector,p_plane,p_direction,p_speed,p_target,p_wait,0,
           p_kind,p_origin,p_line
      from dual
     where not exists(select 1 from active_movers
       where session_token=p_session and sector_id=x_sector and plane=p_plane);
  end;

  procedure dispatch_line(
    p_session varchar2,p_tic number,p_line number,x_special number,p_tag number,
    p_semantics varchar2,x_blue_key number
  ) is
    l_once boolean := instr(p_semantics,'|ONCE|')>0 or p_semantics like '%|ONCE';
    l_count number;l_speed number;l_origin number;l_target number;l_button number;
    l_restore varchar2(32);
  begin
    select trigger_count into l_count from line_state
      where session_token=p_session and linedef_id=p_line for update;
    if l_once and l_count>0 then return; end if;
    if x_special=26 and x_blue_key=0 then
      emit_event(p_session,p_tic,'KEY_DENIED',p_line,'BLUE');
      return;
    end if;
    update line_state set trigger_count=trigger_count+1
      where session_token=p_session and linedef_id=p_line;
    emit_event(p_session,p_tic,'LINE_TRIGGER',p_line,to_char(x_special));

    if x_special=11 then
      update game_sessions set map_status='COMPLETED' where session_token=p_session;
      emit_event(p_session,p_tic,'MAP_COMPLETE',p_line,'E1M1');
      return;
    end if;

    for s in (
      select ss.sector_id,ss.floor_height,ss.ceiling_height
      from sector_state ss join doom_map_sector ms on ms.sector_id=ss.sector_id
      where ss.session_token=p_session and
        ((p_tag<>0 and ms.tag=p_tag) or (p_tag=0 and ss.sector_id=(
          select sd.sector_id from doom_map_linedef ml join doom_map_sidedef sd
            on sd.sidedef_id=ml.left_sidedef_id where ml.linedef_id=p_line)))
      order by ss.sector_id
    ) loop
      if x_special in(1,2,26,117) then
        l_speed:=case when x_special=117 then config_number('WORLD_BLAZE_SPEED')
                      else config_number('WORLD_DOOR_SPEED') end;
        l_target:=door_top(s.sector_id,s.ceiling_height);
        add_mover(p_session,s.sector_id,'CEILING',
          case when x_special=2 then 'DOOR_OPEN' else 'DOOR_RAISE' end,
          1,l_speed,l_target,s.ceiling_height,config_number('WORLD_DOOR_WAIT'),p_line);
      elsif x_special=23 then
        l_target:=neighbor_floor(s.sector_id,s.floor_height);
        add_mover(p_session,s.sector_id,'FLOOR','FLOOR_LOWER',-1,
          config_number('WORLD_LIFT_SPEED'),l_target,s.floor_height,0,p_line);
      elsif x_special in(62,88) then
        l_target:=neighbor_floor(s.sector_id,s.floor_height);
        add_mover(p_session,s.sector_id,'FLOOR','LIFT',-1,
          config_number('WORLD_LIFT_SPEED'),l_target,s.floor_height,
          config_number('WORLD_LIFT_WAIT'),p_line);
      end if;
    end loop;

    if x_special=62 then
      l_button:=config_number('WORLD_BUTTON_TICS');
      select coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                      nullif(sd.lower_texture,'-'),'NONE')
        into l_restore
        from doom_map_linedef ml join doom_map_sidedef sd
          on sd.sidedef_id=ml.right_sidedef_id where ml.linedef_id=p_line;
      update line_state set switch_on=1 where session_token=p_session and linedef_id=p_line;
      merge into active_switches d using(select p_session session_token,p_line linedef_id from dual) x
      on(d.session_token=x.session_token and d.linedef_id=x.linedef_id)
      when matched then update set d.timer_tics=l_button,d.restore_texture=l_restore
      when not matched then insert(session_token,linedef_id,timer_tics,restore_texture)
        values(p_session,p_line,l_button,l_restore);
      emit_event(p_session,p_tic,'SWITCH_ON',p_line,l_restore);
    end if;
  end;

  procedure advance_movers(p_session varchar2,p_tic number) is
    l_height number;l_next number;l_ceiling number;l_player_height number;
    l_blocked number;l_reached boolean;
  begin
    for m in (select * from active_movers where session_token=p_session order by mover_id) loop
      if m.direction=0 then
        update active_movers set timer_tics=greatest(timer_tics-1,0)
          where session_token=p_session and mover_id=m.mover_id;
        if m.timer_tics<=1 then
          update active_movers set direction=case when mover_kind='LIFT' then 1 else -1 end,
            target_height=origin_height where session_token=p_session and mover_id=m.mover_id;
          emit_event(p_session,p_tic,'MOVER_RESUME',m.sector_id,
                     case when m.mover_kind='LIFT' then '1' else '-1' end);
        end if;
        continue;
      end if;
      if m.mover_kind='DOOR_RAISE' and m.direction=-1 and occupant_in_sector(p_session,m.sector_id) then
        select ceiling_height into l_height from sector_state
          where session_token=p_session and sector_id=m.sector_id;
        l_next:=door_top(m.sector_id,l_height);
        update active_movers set direction=1,target_height=l_next
          where session_token=p_session and mover_id=m.mover_id;
        emit_event(p_session,p_tic,'DOOR_REOPEN',m.sector_id);continue;
      end if;
      if m.plane='CEILING' then
        select ceiling_height into l_height from sector_state
          where session_token=p_session and sector_id=m.sector_id;
      else
        select floor_height into l_height from sector_state
          where session_token=p_session and sector_id=m.sector_id;
      end if;
      l_next:=l_height+m.direction*m.speed;
      l_reached:=(m.direction=1 and l_next>=m.target_height) or
                 (m.direction=-1 and l_next<=m.target_height);
      if l_reached then l_next:=m.target_height;end if;

      -- A platform occupant is supported by the moving floor; it is not an
      -- obstruction merely because it is inside the sector.  Doom clips each
      -- supported thing to the new floor height.  A non-crushing lift only
      -- stalls when that clip would leave insufficient headroom.
      if m.plane='FLOOR' and m.direction=1 then
        select ceiling_height into l_ceiling from sector_state
          where session_token=p_session and sector_id=m.sector_id;
        l_player_height:=config_number('PLAYER_HEIGHT');
        select count(*) into l_blocked
        from (
          select p.x,p.y,p.z,l_player_height actor_height
          from players p
          where p.session_token=p_session and p.z<=l_height
          union all
          select o.x,o.y,o.z,o.height
          from mobjs o
          where o.session_token=p_session and o.z<=l_height and o.height>0
        ) actor
        where l_next+actor.actor_height>l_ceiling
          and exists (
            select 1 from table(doom_bsp_locate(actor.x,actor.y)) located
            where located.sector_id=m.sector_id
          );
        if l_blocked>0 then
          emit_event(p_session,p_tic,'LIFT_BLOCKED',m.sector_id);
          continue;
        end if;
      end if;

      if m.plane='CEILING' then
        update sector_state set ceiling_height=l_next
          where session_token=p_session and sector_id=m.sector_id;
      else
        update sector_state set floor_height=l_next
          where session_token=p_session and sector_id=m.sector_id;
        if m.direction=1 then
          update players p set z=l_next
          where p.session_token=p_session and p.z<=l_height
            and exists (
              select 1 from table(doom_bsp_locate(p.x,p.y)) located
              where located.sector_id=m.sector_id
            );
          update mobjs o set z=l_next
          where o.session_token=p_session and o.z<=l_height
            and exists (
              select 1 from table(doom_bsp_locate(o.x,o.y)) located
              where located.sector_id=m.sector_id
            );
        end if;
      end if;
      if l_reached then
        emit_event(p_session,p_tic,'MOVER_REACHED',m.sector_id,to_char(l_next));
        if m.mover_kind='DOOR_RAISE' and m.direction=1 then
          update active_movers set direction=0,timer_tics=wait_tics
            where session_token=p_session and mover_id=m.mover_id;
        elsif m.mover_kind='LIFT' and m.direction=-1 then
          update active_movers set direction=0,timer_tics=wait_tics
            where session_token=p_session and mover_id=m.mover_id;
        else
          delete from active_movers where session_token=p_session and mover_id=m.mover_id;
        end if;
      end if;
    end loop;
  end;

  procedure advance_switches(p_session varchar2,p_tic number) is
  begin
    update active_switches set timer_tics=greatest(timer_tics-1,0)
      where session_token=p_session;
    for s in (select linedef_id from active_switches
               where session_token=p_session and timer_tics=0 order by linedef_id) loop
      update line_state set switch_on=0
        where session_token=p_session and linedef_id=s.linedef_id;
      emit_event(p_session,p_tic,'SWITCH_RESET',s.linedef_id);
      delete from active_switches where session_token=p_session and linedef_id=s.linedef_id;
    end loop;
  end;

  procedure sector_effects(p_session varchar2,p_tic number,p_player number,x_sector number) is
    l_amount number:=config_number('WORLD_DAMAGE_AMOUNT');
    l_strobe_bright number:=config_number('WORLD_STROBE_BRIGHT');
    l_strobe_dark number:=config_number('WORLD_STROBE_DARK');
    l_rng number;l_cursor number;l_max number;l_min number;l_timer number;
  begin
    for s in (select ss.sector_id,ms.special,ss.light_level,ss.light_timer,
        ms.light_level base_light,rt.min_neighbor_light min_light
      from sector_state ss join doom_map_sector ms on ms.sector_id=ss.sector_id
      join doom_sector_special_def d on d.special_id=ms.special
      join doom_sector_runtime_static rt on rt.sector_id=ss.sector_id
      where ss.session_token=p_session and ms.special in(1,7,9,12)
      order by ss.sector_id) loop
      if s.special=12 then
        l_max:=s.base_light;l_min:=s.min_light;
        update sector_state set light_level=case
          when mod(p_tic-1,l_strobe_bright+l_strobe_dark)<l_strobe_bright
          then l_max else l_min end
          where session_token=p_session and sector_id=s.sector_id;
      elsif s.special=1 then
        l_timer:=coalesce(s.light_timer,1)-1;
        if l_timer<=0 then
          select rng_cursor into l_cursor from game_sessions where session_token=p_session;
          select rng_value into l_rng from doom_rng_value where rng_index=mod(l_cursor,256);
          l_max:=s.base_light;l_min:=s.min_light;
          if s.light_level=l_max then l_timer:=bitand(l_rng,7)+1;l_max:=l_min;
          else l_timer:=bitand(l_rng,64)+1;end if;
          update sector_state set light_level=l_max,light_timer=l_timer
            where session_token=p_session and sector_id=s.sector_id;
          update game_sessions set rng_cursor=mod(rng_cursor+1,256) where session_token=p_session;
        else
          update sector_state set light_timer=l_timer where session_token=p_session and sector_id=s.sector_id;
        end if;
      end if;
    end loop;

    if x_sector is not null then
      for s in (select ss.sector_id,ms.special,ss.damage_clock,ss.secret_found
        from sector_state ss join doom_map_sector ms on ms.sector_id=ss.sector_id
        where ss.session_token=p_session and ss.sector_id=x_sector) loop
        if s.special=7 then
          update sector_state set damage_clock=damage_clock+1
            where session_token=p_session and sector_id=s.sector_id;
          if mod(s.damage_clock+1,config_number('WORLD_DAMAGE_PERIOD'))=0 then
            update players set health=greatest(0,health-l_amount),
              alive=case when greatest(0,health-l_amount)=0 then 0 else alive end
              where session_token=p_session and player_id=p_player;
            emit_event(p_session,p_tic,'SECTOR_DAMAGE',l_amount,to_char(s.sector_id));
          end if;
        elsif s.special=9 and s.secret_found=0 then
          update sector_state set secret_found=1 where session_token=p_session and sector_id=s.sector_id;
          update players set secret_count=secret_count+1 where session_token=p_session and player_id=p_player;
          emit_event(p_session,p_tic,'SECRET_FOUND',s.sector_id,'1');
        end if;
      end loop;
    end if;
  end;

  procedure advance(
    p_session in varchar2,p_tic in number,p_previous_x in number,p_previous_y in number,
    p_use_action in number default null
  ) is
    l_player number;l_x number;l_y number;l_angle number;l_blue number;l_use number;
    l_sector number;l_use_range number:=config_number('WORLD_USE_RANGE');
  begin
    select p.player_id,p.x,p.y,p.angle,p.blue_key into l_player,l_x,l_y,l_angle,l_blue
      from game_sessions g join players p
        on p.session_token=g.session_token and p.player_id=g.current_player_id
      where g.session_token=p_session;
    -- USE_ACTION is accepted only through the exact WORLD_USE_RANGE geometry
    -- query below; the command never identifies an actionable line.
    if p_use_action is null then
      select command_row.use_action into l_use
      from game_sessions session_row
      join tic_commands command_row
        on command_row.session_token=session_row.session_token
       and command_row.lineage=case
         when regexp_like(session_row.save_lineage,'^[0-9a-f]{64}$')
           then session_row.save_lineage else rpad('0',64,'0') end
       and command_row.tic=p_tic
       and command_row.command_ordinal=0
      where session_row.session_token=p_session;
    else
      l_use:=p_use_action;
    end if;
    begin
      select sector_id into l_sector from table(doom_bsp_locate(l_x,l_y)) where rownum=1;
    exception when no_data_found then l_sector:=null;end;

    if l_use=1 then
      for hit in (
        select * from (
          select q.*,row_number() over(order by ray_t,linedef_id) hit_rank
          from (
            select g.*,((g.x1-l_x)*g.sy-(g.y1-l_y)*g.sx)/nullif(g.den,0) ray_t,
              ((g.x1-l_x)*g.ry-(g.y1-l_y)*g.rx)/nullif(g.den,0) segment_t
            from (
              select ml.linedef_id,ml.special,ml.tag,d.semantics,v1.x x1,v1.y y1,
                v2.x-v1.x sx,v2.y-v1.y sy,
                cos(l_angle*acos(-1)/180) rx,sin(l_angle*acos(-1)/180) ry,
                cos(l_angle*acos(-1)/180)*(v2.y-v1.y)-sin(l_angle*acos(-1)/180)*(v2.x-v1.x) den
              from doom_map_linedef ml join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
              join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
              join doom_linedef_special_def d on d.special_id=ml.special
              where instr(d.semantics,'USE|')=1
                and ((v2.x-v1.x)*(l_y-v1.y)-(v2.y-v1.y)*(l_x-v1.x))<0
            ) g where abs(g.den)>0
          ) q where q.ray_t between 0 and l_use_range and q.segment_t between 0 and 1
        ) where hit_rank=1
      ) loop
        dispatch_line(p_session,p_tic,hit.linedef_id,hit.special,hit.tag,hit.semantics,l_blue);
      end loop;
    end if;

    -- A zero-length player segment cannot cross a WALK trigger.  Avoid the
    -- full special-linedef determinant scan on stationary/turn-only tics.
    if l_x<>p_previous_x or l_y<>p_previous_y then
    for crossed in (
      select * from (
        select ml.linedef_id,ml.special,ml.tag,d.semantics,
          ((v2.x-v1.x)*(p_previous_y-v1.y)-(v2.y-v1.y)*(p_previous_x-v1.x)) prior_side,
          ((v2.x-v1.x)*(l_y-v1.y)-(v2.y-v1.y)*(l_x-v1.x)) current_side,
          ((v1.x-p_previous_x)*(l_y-p_previous_y)-(v1.y-p_previous_y)*(l_x-p_previous_x)) /
            nullif((l_x-p_previous_x)*(v2.y-v1.y)-(l_y-p_previous_y)*(v2.x-v1.x),0) segment_t,
          ((v1.x-p_previous_x)*(v2.y-v1.y)-(v1.y-p_previous_y)*(v2.x-v1.x)) /
            nullif((l_x-p_previous_x)*(v2.y-v1.y)-(l_y-p_previous_y)*(v2.x-v1.x),0) cross_t
        from doom_map_linedef ml join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
          join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
          join doom_linedef_special_def d on d.special_id=ml.special
        where instr(d.semantics,'WALK|')=1
      ) where prior_side<0 and current_side>0 and cross_t>0 and cross_t<1
          and segment_t>0 and segment_t<1 order by cross_t,linedef_id
    ) loop
      dispatch_line(p_session,p_tic,crossed.linedef_id,crossed.special,crossed.tag,crossed.semantics,l_blue);
    end loop;
    end if;

    advance_movers(p_session,p_tic);
    advance_switches(p_session,p_tic);
    sector_effects(p_session,p_tic,l_player,l_sector);
  end;
end doom_world_machines;
/
