-- T7.1 database-owned inventory and combat advancement.  This package is a
-- participant in DOOM_TIC_TX's transaction and never owns its boundary.
create or replace package doom_combat authid definer as
  procedure advance(p_session_token in varchar2,p_tic in number);
end doom_combat;
/

create or replace package body doom_combat as
  c_pi constant number := acos(-1);

  procedure emit_event(
    p_session varchar2,p_tic number,p_type varchar2,
    p_actor number default null,p_target number default null,
    p_number number default null,p_text varchar2 default null
  ) is
    l_ordinal number;
  begin
    select coalesce(max(event_ordinal)+1,0) into l_ordinal
      from game_events where session_token=p_session and tic=p_tic;
    insert into game_events(session_token,tic,event_ordinal,event_type,
      actor_mobj_id,target_mobj_id,number_value,text_value)
    values(p_session,p_tic,l_ordinal,p_type,p_actor,p_target,p_number,p_text);
  end;

  function rng_draw(p_session varchar2) return number is
    l_cursor number;l_value number;
  begin
    select rng_cursor into l_cursor from game_sessions
      where session_token=p_session for update;
    select rng_value into l_value from doom_rng_value
      where rng_index=mod(l_cursor,256);
    update game_sessions set rng_cursor=mod(l_cursor+1,256)
      where session_token=p_session;
    return l_value;
  end;

  function ammo_count(
    p_bullets number,p_shells number,p_rockets number,p_cells number,
    p_type varchar2
  ) return number is
  begin
    return case p_type when 'BULLET' then p_bullets when 'SHELL' then p_shells
      when 'ROCKET' then p_rockets when 'CELL' then p_cells else 0 end;
  end;

  function has_ammo(
    p_bullets number,p_shells number,p_rockets number,p_cells number,
    p_type varchar2,p_cost number
  ) return boolean is
  begin
    return p_type='NONE' or ammo_count(p_bullets,p_shells,p_rockets,p_cells,p_type)>=p_cost;
  end;

  procedure consume_ammo(
    p_session varchar2,p_player number,p_type varchar2,p_cost number
  ) is
  begin
    update players set
      ammo_bullets=ammo_bullets-case when p_type='BULLET' then p_cost else 0 end,
      ammo_shells=ammo_shells-case when p_type='SHELL' then p_cost else 0 end,
      ammo_rockets=ammo_rockets-case when p_type='ROCKET' then p_cost else 0 end,
      ammo_cells=ammo_cells-case when p_type='CELL' then p_cost else 0 end
    where session_token=p_session and player_id=p_player;
  end;

  function first_blocking_depth(
    p_x0 number,p_y0 number,p_x1 number,p_y1 number
  ) return number is
    l_depth number;
  begin
    -- Exact bounded segment intersection; a one-sided line or closed opening is
    -- blocking.  This is shared by splash occlusion and projectile collision.
    select min(hit_t) into l_depth from (
      select l.linedef_id,
        ((v1.x-p_x0)*(p_y1-p_y0)-(v1.y-p_y0)*(p_x1-p_x0)) /
          nullif((p_x1-p_x0)*(v2.y-v1.y)-(p_y1-p_y0)*(v2.x-v1.x),0) as hit_u,
        ((v1.x-p_x0)*(v2.y-v1.y)-(v1.y-p_y0)*(v2.x-v1.x)) /
          nullif((p_x1-p_x0)*(v2.y-v1.y)-(p_y1-p_y0)*(v2.x-v1.x),0) as hit_t,
        case when l.left_sidedef_id is null then 1
             when least(sr.ceiling_height,sl.ceiling_height)
                  <=greatest(sr.floor_height,sl.floor_height) then 1 else 0 end blocking
      from doom_map_linedef l
      join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
      join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
      join doom_map_sidedef dr on dr.sidedef_id=l.right_sidedef_id
      join doom_map_sector sr on sr.sector_id=dr.sector_id
      left join doom_map_sidedef dl on dl.sidedef_id=l.left_sidedef_id
      left join doom_map_sector sl on sl.sector_id=dl.sector_id
    ) where blocking=1 and hit_t>0 and hit_t<1 and hit_u between 0 and 1;
    return l_depth;
  end;

  function line_blocks_segment(
    p_x0 number,p_y0 number,p_x1 number,p_y1 number
  ) return number is
  begin
    return case when first_blocking_depth(p_x0,p_y0,p_x1,p_y1) is null
      then 0 else 1 end;
  end;

  procedure damage_player(
    p_session varchar2,p_tic number,p_player number,p_damage number,p_source number
  ) is
    l_armor number;l_type number;l_absorb number;l_health_damage number;
  begin
    select armor,armor_type into l_armor,l_type from players
      where session_token=p_session and player_id=p_player for update;
    l_absorb:=least(l_armor,floor(p_damage*case l_type when 2 then 0.5 when 1 then 0.333 else 0 end));
    l_health_damage:=p_damage-l_absorb;
    update players set armor=armor-l_absorb,health=greatest(0,health-l_health_damage),
      alive=case when health-l_health_damage<=0 then 0 else alive end
      where session_token=p_session and player_id=p_player;
    emit_event(p_session,p_tic,'PLAYER_DAMAGE',p_source,null,p_damage);
  end;

  procedure splash_damage(
    p_session varchar2,p_tic number,p_x number,p_y number,
    p_radius number,p_damage number,p_source number
  );

  procedure damage_mobj(
    p_session varchar2,p_tic number,p_target number,p_damage number,p_source number
  ) is
    l_type number;l_health number;l_x number;l_y number;l_exploded number;
  begin
    update mobjs set health=greatest(0,health-p_damage)
      where session_token=p_session and mobj_id=p_target and health>0
      returning thing_type,health,x,y,exploded into l_type,l_health,l_x,l_y,l_exploded;
    emit_event(p_session,p_tic,'DAMAGE',p_source,p_target,p_damage);
    if l_type=2035 and l_health=0 and l_exploded=0 then
      update mobjs set exploded=1 where session_token=p_session and mobj_id=p_target;
      emit_event(p_session,p_tic,'BARREL_EXPLODE',p_source,p_target,128);
      -- Stable barrel chain expansion: recursive victims are always selected by
      -- authoritative mobj id and an exploded barrel is never expanded twice.
      splash_damage(p_session,p_tic,l_x,l_y,128,128,p_target);
    end if;
  exception when no_data_found then null;
  end;

  procedure splash_damage(
    p_session varchar2,p_tic number,p_x number,p_y number,
    p_radius number,p_damage number,p_source number
  ) is
    l_distance number;l_amount number;
  begin
    -- SPLASH victims use bounded Euclidean DISTANCE falloff and exact OCCLUSION
    -- by BLOCKING geometry; SQRT is deliberate and deterministic.
    for victim in (
      select mobj_id,x,y from mobjs
      where session_token=p_session and health>0 and mobj_id<>p_source
        and sqrt(power(x-p_x,2)+power(y-p_y,2))<=p_radius
      order by mobj_id
    ) loop
      l_distance:=sqrt(power(victim.x-p_x,2)+power(victim.y-p_y,2));
      l_amount:=greatest(0,p_damage-floor(l_distance));
      if l_amount>0 and line_blocks_segment(p_x,p_y,victim.x,victim.y)=0 then
        damage_mobj(p_session,p_tic,victim.mobj_id,l_amount,p_source);
      end if;
    end loop;
    for player_victim in (
      select player_id,x,y from players where session_token=p_session and alive=1
      order by player_id
    ) loop
      l_distance:=sqrt(power(player_victim.x-p_x,2)+power(player_victim.y-p_y,2));
      l_amount:=greatest(0,p_damage-floor(l_distance));
      if l_distance<=p_radius and l_amount>0
         and line_blocks_segment(p_x,p_y,player_victim.x,player_victim.y)=0 then
        damage_player(p_session,p_tic,player_victim.player_id,l_amount,p_source);
      end if;
    end loop;
  end;

  procedure remove_mobj(p_session varchar2,p_mobj_id number) is
  begin
    -- Doom actor pointers are weak references.  Relational foreign keys make
    -- their lifetime rule explicit: detach every inbound pointer in the same
    -- session before removing the actor.  This keeps the transaction valid
    -- when deferred self-references are checked by SAVE/LOAD or the boundary.
    update mobjs set target_mobj_id=null
      where session_token=p_session and target_mobj_id=p_mobj_id;
    update mobjs set tracer_mobj_id=null
      where session_token=p_session and tracer_mobj_id=p_mobj_id;
    update mobjs set owner_mobj_id=null
      where session_token=p_session and owner_mobj_id=p_mobj_id;
    delete from mobjs
      where session_token=p_session and mobj_id=p_mobj_id;
  end;

  procedure apply_pickups(
    p_session varchar2,p_tic number,p_player number,p_x number,p_y number
  ) is
    l_changed boolean;l_old number;l_new number;l_cap number;l_mask number;
    l_backpack number;
  begin
    -- DOOM_PICKUP_DEF is joined to MOBJS by THING_TYPE; behavior never dispatches
    -- on map ids or procedural type literals.
    for item in (
      select m.mobj_id,p.*
      from doom_pickup_def p join mobjs m on m.thing_type=p.thing_type
      where m.session_token=p_session
        and sqrt(power(m.x-p_x,2)+power(m.y-p_y,2))<=m.radius+16
      order by m.mobj_id
    ) loop
      l_changed:=false;
      select backpack,weapon_mask into l_backpack,l_mask from players
        where session_token=p_session and player_id=p_player for update;

      if item.grants_backpack=1 and l_backpack=0 then
        update players set backpack=1 where session_token=p_session and player_id=p_player;
        l_backpack:=1;l_changed:=true;
      end if;
      if item.grants_key is not null then
        update players set
          blue_key=case when item.grants_key='BLUE' then 1 else blue_key end,
          yellow_key=case when item.grants_key='YELLOW' then 1 else yellow_key end,
          red_key=case when item.grants_key='RED' then 1 else red_key end
        where session_token=p_session and player_id=p_player
          and ((item.grants_key='BLUE' and blue_key=0)
            or (item.grants_key='YELLOW' and yellow_key=0)
            or (item.grants_key='RED' and red_key=0));
        if sql%rowcount>0 then l_changed:=true;end if;
      end if;
      if item.grants_weapon_id is not null then
        select power(2,slot_number-1) into l_mask from doom_weapon_def
          where weapon_id=item.grants_weapon_id;
        update players set weapon_mask=weapon_mask+l_mask
          where session_token=p_session and player_id=p_player
            and bitand(weapon_mask,l_mask)=0;
        if sql%rowcount>0 then l_changed:=true;end if;
      end if;
      if item.ammo_type is not null then
        select case when l_backpack=1 then backpack_cap else normal_cap end
          into l_cap from doom_ammo_def where ammo_type=item.ammo_type;
        select case item.ammo_type
          when 'BULLET' then ammo_bullets when 'SHELL' then ammo_shells
          when 'ROCKET' then ammo_rockets when 'CELL' then ammo_cells else 0 end
          into l_old from players where session_token=p_session and player_id=p_player;
        l_new:=least(l_cap,l_old+item.amount);
        if l_new<>l_old then
          update players set
            ammo_bullets=case when item.ammo_type='BULLET' then l_new else ammo_bullets end,
            ammo_shells=case when item.ammo_type='SHELL' then l_new else ammo_shells end,
            ammo_rockets=case when item.ammo_type='ROCKET' then l_new else ammo_rockets end,
            ammo_cells=case when item.ammo_type='CELL' then l_new else ammo_cells end
          where session_token=p_session and player_id=p_player;
          l_changed:=true;
        end if;
      end if;
      if item.health_amount is not null then
        select health into l_old from players where session_token=p_session and player_id=p_player;
        l_new:=least(item.health_cap,l_old+item.health_amount);
        if l_new<>l_old then
          update players set health=l_new where session_token=p_session and player_id=p_player;
          l_changed:=true;
        end if;
      end if;
      if item.health_minimum is not null then
        update players set health=greatest(health,item.health_minimum)
          where session_token=p_session and player_id=p_player and health<item.health_minimum;
        if sql%rowcount>0 then l_changed:=true;end if;
      end if;
      if item.armor_amount is not null then
        select armor into l_old from players where session_token=p_session and player_id=p_player;
        l_new:=least(item.armor_cap,l_old+item.armor_amount);
        if l_new<>l_old then
          update players set armor=l_new where session_token=p_session and player_id=p_player;
          l_changed:=true;
        end if;
      end if;
      if item.armor_set is not null then
        update players set armor=item.armor_set,armor_type=item.armor_type
          where session_token=p_session and player_id=p_player and armor<item.armor_set;
        if sql%rowcount>0 then l_changed:=true;end if;
      end if;
      if item.grants_power='BERSERK' then
        update players set power_berserk=1
          where session_token=p_session and player_id=p_player and power_berserk=0;
        if sql%rowcount>0 then
          emit_event(p_session,p_tic,'POWER_GRANTED',null,null,null,item.grants_power);
          l_changed:=true;
        end if;
      end if;
      if l_changed then
        remove_mobj(p_session,item.mobj_id);
        update players set item_count=item_count+1
          where session_token=p_session and player_id=p_player;
        emit_event(p_session,p_tic,'PICKUP',null,item.mobj_id,item.thing_type,item.pickup_kind);
      end if;
    end loop;
  end;

  procedure choose_weapon(p_session varchar2,p_tic number,p_player number) is
    l_slot number;l_mask number;l_owned_mask number;l_weapon varchar2(32);l_selected varchar2(32);
    l_ammo varchar2(32);l_cost number;l_b number;l_s number;l_r number;l_c number;
  begin
    select coalesce(max(command_row.weapon_slot),0) into l_slot
    from game_sessions session_row
    left join tic_commands command_row
      on command_row.session_token=session_row.session_token
     and command_row.lineage=case
       when regexp_like(session_row.save_lineage,'^[0-9a-f]{64}$')
         then session_row.save_lineage else rpad('0',64,'0') end
     and command_row.tic=p_tic
     and command_row.command_ordinal=0
    where session_row.session_token=p_session;
    if l_slot=0 then return;end if;
    begin
      select w.weapon_id,w.ammo_type,w.ammo_cost,p.selected_weapon,
        p.ammo_bullets,p.ammo_shells,p.ammo_rockets,p.ammo_cells,p.weapon_mask,
        power(2,w.slot_number-1)
      into l_weapon,l_ammo,l_cost,l_selected,l_b,l_s,l_r,l_c,l_owned_mask,l_mask
      from doom_weapon_def w join players p on p.session_token=p_session and p.player_id=p_player
      where w.slot_number=l_slot;
      if bitand(l_owned_mask,l_mask)>0
         and has_ammo(l_b,l_s,l_r,l_c,l_ammo,l_cost) and l_weapon<>l_selected then
        update players set pending_weapon=l_weapon,
          weapon_state='WEAPON_'||selected_weapon||'_LOWER',weapon_state_tics=3
        where session_token=p_session and player_id=p_player;
        emit_event(p_session,p_tic,'WEAPON_LOWER',null,null,l_slot,l_weapon);
      end if;
    exception when no_data_found then null;
    end;
  end;

  procedure advance_weapon_state(p_session varchar2,p_tic number,p_player number) is
    l_state varchar2(64);l_pending varchar2(32);l_next varchar2(64);l_tics number;
  begin
    select weapon_state,pending_weapon,weapon_state_tics into l_state,l_pending,l_tics
      from players where session_token=p_session and player_id=p_player for update;
    update players set flash_state_tics=greatest(flash_state_tics-1,0),
      flash_state=case when flash_state_tics<=1 then null else flash_state end
      where session_token=p_session and player_id=p_player;
    if l_tics>1 then
      update players set weapon_state_tics=l_tics-1
        where session_token=p_session and player_id=p_player;
    elsif l_tics=1 then
      select next_state_id,tics into l_next,l_tics from doom_state_def where state_id=l_state;
      if l_state like '%_LOWER' and l_pending is not null then
        update players set selected_weapon=l_pending,pending_weapon=null,
          weapon_state='WEAPON_'||l_pending||'_RAISE',weapon_state_tics=3
          where session_token=p_session and player_id=p_player;
        emit_event(p_session,p_tic,'WEAPON_RAISE',null,null,null,l_pending);
      else
        update players set weapon_state=l_next,weapon_state_tics=greatest(l_tics,0)
          where session_token=p_session and player_id=p_player;
      end if;
    end if;
  end;

  procedure hitscan_attack(
    p_session varchar2,p_tic number,p_player number,p_pellets number,
    p_multiplier number,p_spread_scale number
  ) is
    l_x number;l_y number;l_spread number;l_damage number;
    l_dx number;l_dy number;l_ray_length number;l_wall number;l_target number;l_depth number;
    l_column number;
  begin
    select x,y into l_x,l_y from players
      where session_token=p_session and player_id=p_player;
    for pellet in 1..p_pellets loop
      l_spread:=(rng_draw(p_session)-rng_draw(p_session))*p_spread_scale;
      l_damage:=(mod(rng_draw(p_session),3)+1)*p_multiplier;
      l_column:=least(319,greatest(0,floor((tan(l_spread)+1)*160)));
      -- DOOM_R1_RAYS feeds the reviewed LINEDEF INTERSECTION path.  The
      -- ordered-spread column selects the exact DEPTH/DISTANCE bound.
      select r.ray_x,r.ray_y,sqrt(r.ray_length_squared)
        into l_dx,l_dy,l_ray_length
        from table(doom_r1_rays(p_session)) r where r.column_no=l_column;
      l_dx:=l_dx/l_ray_length;l_dy:=l_dy/l_ray_length;
      select min(h.hit_t)*l_ray_length into l_wall
      from table(doom_r1_hits(p_session)) h
      where h.column_no=l_column and h.is_solid=1;
      begin
        select mobj_id,depth into l_target,l_depth from (
          select m.mobj_id,
            (m.x-l_x)*l_dx+(m.y-l_y)*l_dy depth,
            abs((m.x-l_x)*l_dy-(m.y-l_y)*l_dx) miss,m.radius
          from mobjs m join doom_thing_type_def td on td.thing_type=m.thing_type
          where m.session_token=p_session and m.health>0
            and td.category in('monster','barrel')
          order by depth,m.mobj_id
        ) where depth>0 and miss<=radius and (l_wall is null or depth<l_wall)
          fetch first 1 row only;
        damage_mobj(p_session,p_tic,l_target,l_damage,null);
        emit_event(p_session,p_tic,'HITSCAN_HIT',null,l_target,l_damage,to_char(l_spread));
      exception when no_data_found then
        emit_event(p_session,p_tic,'HITSCAN_MISS',null,null,null,to_char(l_spread));
      end;
    end loop;
  end;

  procedure spawn_projectile(
    p_session varchar2,p_tic number,p_player number,p_kind varchar2
  ) is
    l_id number;l_x number;l_y number;l_z number;l_angle number;
    d doom_projectile_def%rowtype;
  begin
    select * into d from doom_projectile_def where projectile_kind=p_kind;
    select x,y,z,angle into l_x,l_y,l_z,l_angle from players
      where session_token=p_session and player_id=p_player;
    select coalesce(max(mobj_id)+1,1) into l_id from mobjs where session_token=p_session;
    insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
      momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
      target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,
      owner_mobj_id,projectile_kind,exploded)
    values(p_session,l_id,d.thing_type,d.spawn_state_id,1,l_x,l_y,l_z+32,
      cos(l_angle*c_pi/180)*d.speed,sin(l_angle*c_pi/180)*d.speed,0,
      l_angle,d.radius,d.height,1,0,null,null,0,null,null,p_kind,0);
    emit_event(p_session,p_tic,'PROJECTILE_SPAWN',l_id,null,d.speed,p_kind);
  end;

  procedure fire_weapon(p_session varchar2,p_tic number,p_player number) is
    l_fire number;l_b number;l_s number;l_r number;l_c number;
    l_state varchar2(64);
    w doom_weapon_def%rowtype;
  begin
    select coalesce(max(command_row.fire),0) into l_fire
    from game_sessions session_row
    left join tic_commands command_row
      on command_row.session_token=session_row.session_token
     and command_row.lineage=case
       when regexp_like(session_row.save_lineage,'^[0-9a-f]{64}$')
         then session_row.save_lineage else rpad('0',64,'0') end
     and command_row.tic=p_tic
     and command_row.command_ordinal=0
    where session_row.session_token=p_session;
    if l_fire=0 then
      update players set refire=0 where session_token=p_session and player_id=p_player;
      return;
    end if;
    select weapon_state into l_state from players
      where session_token=p_session and player_id=p_player;
    if l_state not like '%_READY' and l_state not like '%_REFIRE' then return;end if;
    select wd.* into w from doom_weapon_def wd join players p
      on p.selected_weapon=wd.weapon_id
      where p.session_token=p_session and p.player_id=p_player;
    select ammo_bullets,ammo_shells,ammo_rockets,ammo_cells
      into l_b,l_s,l_r,l_c from players where session_token=p_session and player_id=p_player;
    if not has_ammo(l_b,l_s,l_r,l_c,w.ammo_type,w.ammo_cost) then
      emit_event(p_session,p_tic,'DRY_FIRE');return;
    end if;
    consume_ammo(p_session,p_player,w.ammo_type,w.ammo_cost);
    update players set weapon_state=w.fire_state_id,weapon_state_tics=4,
      flash_state=w.flash_state_id,flash_state_tics=2,refire=refire+1
      where session_token=p_session and player_id=p_player;
    if w.attack_kind in('HITSCAN','MELEE') then
      hitscan_attack(p_session,p_tic,p_player,w.pellet_count,w.damage_multiplier,w.spread_scale);
    else
      spawn_projectile(p_session,p_tic,p_player,w.projectile_kind);
    end if;
  end;

  procedure advance_projectiles(p_session varchar2,p_tic number) is
    l_nx number;l_ny number;l_target number;l_depth number;l_wall number;
    d doom_projectile_def%rowtype;
  begin
    -- PROJECTILE MOMENTUM advances over a bounded SWEEP; exact INTERSECTION and
    -- actor COLLISION choose the nearest stable impact before mutation.
    for projectile in (
      select * from mobjs where session_token=p_session and projectile_kind is not null
      order by mobj_id
    ) loop
      select * into d from doom_projectile_def where projectile_kind=projectile.projectile_kind;
      l_nx:=projectile.x+projectile.momentum_x;
      l_ny:=projectile.y+projectile.momentum_y;
      l_wall:=first_blocking_depth(projectile.x,projectile.y,l_nx,l_ny);
      begin
        select mobj_id,depth into l_target,l_depth from (
          select m.mobj_id,
            ((m.x-projectile.x)*projectile.momentum_x+
             (m.y-projectile.y)*projectile.momentum_y) /
             nullif(power(projectile.momentum_x,2)+power(projectile.momentum_y,2),0) depth,
            abs((m.x-projectile.x)*projectile.momentum_y-
                (m.y-projectile.y)*projectile.momentum_x) /
             nullif(sqrt(power(projectile.momentum_x,2)+power(projectile.momentum_y,2)),0) miss,
            m.radius
          from mobjs m join doom_thing_type_def td on td.thing_type=m.thing_type
          where m.session_token=p_session and m.mobj_id<>projectile.mobj_id
            and m.health>0 and m.projectile_kind is null
            and td.category in('monster','barrel')
          order by depth,m.mobj_id
        ) where depth between 0 and 1 and miss<=radius+d.radius fetch first 1 row only;
      exception when no_data_found then l_target:=null;
      end;
      if l_wall is not null or l_target is not null then
        if l_target is not null and (l_wall is null or l_depth<l_wall) then
          damage_mobj(p_session,p_tic,l_target,d.damage,projectile.mobj_id);
        elsif l_wall is not null then
          l_target:=null;
        end if;
        remove_mobj(p_session,projectile.mobj_id);
        emit_event(p_session,p_tic,'PROJECTILE_IMPACT',projectile.mobj_id,l_target,d.damage,d.projectile_kind);
        if d.splash_radius>0 then
          splash_damage(p_session,p_tic,l_nx,l_ny,d.splash_radius,d.splash_damage,projectile.mobj_id);
        end if;
      else
        update mobjs set x=l_nx,y=l_ny where session_token=p_session and mobj_id=projectile.mobj_id;
      end if;
    end loop;
  end;

  procedure advance(p_session_token in varchar2,p_tic in number) is
    l_player number;l_x number;l_y number;
  begin
    select current_player_id into l_player from game_sessions
      where session_token=p_session_token for update;
    select x,y into l_x,l_y from players
      where session_token=p_session_token and player_id=l_player for update;
    apply_pickups(p_session_token,p_tic,l_player,l_x,l_y);
    choose_weapon(p_session_token,p_tic,l_player);
    advance_weapon_state(p_session_token,p_tic,l_player);
    fire_weapon(p_session_token,p_tic,l_player);
    advance_projectiles(p_session_token,p_tic);
  end;
end doom_combat;
/
