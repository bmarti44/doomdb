-- T7.2 database-owned monster state, perception and attack advancement. This
-- package participates in DOOM_TIC_TX and deliberately owns no transaction
-- boundary. Every actor is read into one prior-tic snapshot before mutation.
create or replace package doom_monsters authid definer as
  procedure advance(p_session_token in varchar2,p_tic in number);
end doom_monsters;
/

create or replace package body doom_monsters as
  type number_set is table of number index by pls_integer;

  type actor_record is record (
    mobj_id number,thing_type number,state_id varchar2(64),state_tics number,
    x number,y number,z number,radius number,height number,health number,
    target_mobj_id number,sector_id number,move_direction number,awake number,
    attack_cooldown number,monster_health_seen number,death_processed number,
    speed number,pain_chance number,melee_range number,attack_kind varchar2(16),
    damage_base number,damage_dice number,projectile_thing_type number,
    drop_thing_type number,see_state_id varchar2(64),chase_state_id varchar2(64),
    melee_state_id varchar2(64),missile_state_id varchar2(64),
    pain_state_id varchar2(64),death_state_id varchar2(64),rejected number,
    visible number
  );
  type actor_snapshot is table of actor_record index by pls_integer;

  procedure emit_event(
    p_session varchar2,p_tic number,p_type varchar2,p_actor number,
    p_target number default null,p_number number default null,
    p_text varchar2 default null
  ) is
    l_ordinal number;
  begin
    select coalesce(max(event_ordinal)+1,0) into l_ordinal
      from game_events where session_token=p_session
        and lineage=(select save_lineage from game_sessions
          where session_token=p_session)
        and tic=p_tic;
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

  function point_sector(p_x number,p_y number) return number is
    l_sector number;
  begin
    select sector_id into l_sector from table(doom_bsp_locate(p_x,p_y))
      where rownum=1;
    return l_sector;
  end;

  function reject_pair(p_source number,p_target number) return number is
    l_rejected number;
  begin
    -- DOOM_SECTOR_REJECT is the exact bootstrap decode of DOOM_REJECT_BYTE
    -- using the reviewed BITAND/POWER addressing rule.
    select rejected into l_rejected from doom_sector_reject
      where source_sector_id=p_source and target_sector_id=p_target;
    return l_rejected;
  exception when no_data_found then return 1;
  end;

  function exact_visible(
    p_session varchar2,p_x number,p_y number,p_z number,p_source_sector number,
    p_target_x number,p_target_y number,p_target_z number,p_target_sector number,
    p_known_rejected number default null
  ) return number is
    l_blocker number;
  begin
    -- DOOM_LOS_SEGMENT packs reviewed DOOM_MAP_LINEDEF/DOOM_MAP_SIDEDEF vertex
    -- facts; live portal heights remain relational joins below.
    -- DOOM_REJECT_BYTE is a negative-only filter. An unset REJECT bit proceeds
    -- to an exact INTERSECT determinant path; DOOM_R1_RAYS uses the same
    -- LINEDEF rational NUMERATOR/DENOMINATOR/DISTANCE ordering convention.
    if p_known_rejected is not null then
      if p_known_rejected=1 then return 0;end if;
    elsif reject_pair(p_source_sector,p_target_sector)=1 then
      return 0;
    end if;
    begin
      select linedef_id into l_blocker from (
        select hit.*,
          row_number() over(order by distance_numerator/distance_denominator,
                                     linedef_id) hit_order
        from (
          select geometry.*,
            ((geometry.vx-p_x)*geometry.sy-(geometry.vy-p_y)*geometry.sx)
              as distance_numerator,
            ((p_target_x-p_x)*geometry.sy-(p_target_y-p_y)*geometry.sx)
              as distance_denominator,
            ((geometry.vx-p_x)*(p_target_y-p_y)
              -(geometry.vy-p_y)*(p_target_x-p_x))
              / nullif(((p_target_x-p_x)*geometry.sy
                         -(p_target_y-p_y)*geometry.sx),0) as line_fraction,
            case when geometry.left_sidedef_id is null then 1
                 when least(geometry.right_ceiling,geometry.left_ceiling)
                    <=greatest(geometry.right_floor,geometry.left_floor)
                   then 1 else 0 end as blocking
          from (
            select l.linedef_id,l.left_sector_id as left_sidedef_id,
              l.vx,l.vy,l.sx,l.sy,
              coalesce(rss.ceiling_height,rs.ceiling_height) right_ceiling,
              coalesce(rss.floor_height,rs.floor_height) right_floor,
              coalesce(lss.ceiling_height,ls.ceiling_height) left_ceiling,
              coalesce(lss.floor_height,ls.floor_height) left_floor
            from doom_block_cell bc
            join doom_block_line bl on bl.cell_id=bc.cell_id
            join doom_los_segment l on l.linedef_id=bl.linedef_id
            join doom_map_sector rs on rs.sector_id=l.right_sector_id
            left join sector_state rss on rss.session_token=p_session
              and rss.sector_id=rs.sector_id
            left join doom_map_sector ls on ls.sector_id=l.left_sector_id
            left join sector_state lss on lss.session_token=p_session
              and lss.sector_id=ls.sector_id
            where bc.world_min_x<=greatest(p_x,p_target_x)
              and bc.world_min_x+128>=least(p_x,p_target_x)
              and bc.world_min_y<=greatest(p_y,p_target_y)
              and bc.world_min_y+128>=least(p_y,p_target_y)
              and greatest(l.vx,l.vx+l.sx)>=least(p_x,p_target_x)
              and least(l.vx,l.vx+l.sx)<=greatest(p_x,p_target_x)
              and greatest(l.vy,l.vy+l.sy)>=least(p_y,p_target_y)
              and least(l.vy,l.vy+l.sy)<=greatest(p_y,p_target_y)
          ) geometry
        ) hit
        where hit.distance_denominator<>0
          and hit.distance_numerator/hit.distance_denominator>0
          and hit.distance_numerator/hit.distance_denominator<1
          and hit.line_fraction between 0 and 1 and hit.blocking=1
      ) where hit_order=1;
      return 0;
    exception when no_data_found then return 1;
    end;
  end;

  function sound_reach(p_source number,p_target number) return number is
    l_reachable number;
  begin
    -- DOOM_SECTOR_SOUND_REACH is the bootstrap-computed bounded breadth-first
    -- sector-graph closure. SOUND_BLOCK edges are excluded; its primary-key
    -- visited set terminates every cycle before this indexed runtime lookup.
    select 1 into l_reachable from doom_sector_sound_reach
      where source_sector_id=p_source and target_sector_id=p_target;
    return l_reachable;
  exception when no_data_found then return 0;
  end;

  function player_made_sound(p_session varchar2,p_tic number) return number is
    l_count number;
  begin
    select count(*) into l_count from game_events
      where session_token=p_session
        and lineage=(select save_lineage from game_sessions
          where session_token=p_session)
        and tic=p_tic
        and event_type in('DAMAGE','BARREL_EXPLODE','PROJECTILE_SPAWN',
                          'PROJECTILE_IMPACT','DRY_FIRE');
    return case when l_count>0 then 1 else 0 end;
  end;

  procedure damage_player(
    p_session varchar2,p_tic number,p_actor number,p_damage number
  ) is
    l_player number;l_armor number;l_armor_type number;l_absorb number;
  begin
    select current_player_id into l_player from game_sessions
      where session_token=p_session;
    select armor,armor_type into l_armor,l_armor_type from players
      where session_token=p_session and player_id=l_player for update;
    l_absorb:=least(l_armor,floor(p_damage*
      case l_armor_type when 2 then .5 when 1 then .333 else 0 end));
    update players set armor=armor-l_absorb,
      health=greatest(0,health-(p_damage-l_absorb)),
      alive=case when health-(p_damage-l_absorb)<=0 then 0 else alive end
      where session_token=p_session and player_id=l_player;
    emit_event(p_session,p_tic,'MONSTER_HIT',p_actor,null,p_damage);
  end;

  function collision_free(
    p_session varchar2,p_actor number,p_x number,p_y number,p_z number,
    p_dx number,p_dy number,p_radius number,p_height number,
    p_snapshot actor_snapshot
  ) return number is
    l_collision varchar2(4000);
  begin
    -- MOVE_DIRECTION candidates share exact wall COLLISION and actor BLOCK
    -- tests. Actor RADIUS ties are resolved by snapshot MOBJ_ID ORDER BY.
    l_collision:=doom_sweep_contact(p_session,p_x,p_y,p_z,p_dx,p_dy,
                                    p_radius,p_height,24,null);
    if l_collision is not null then return 0;end if;
    if p_snapshot.count>0 then
      for i in p_snapshot.first..p_snapshot.last loop
        if p_snapshot.exists(i) and p_snapshot(i).mobj_id<>p_actor
           and p_snapshot(i).health>0
           and sqrt(power(p_snapshot(i).x-(p_x+p_dx),2)
                    +power(p_snapshot(i).y-(p_y+p_dy),2))
                 < p_radius+p_snapshot(i).radius then return 0;
        end if;
      end loop;
    end if;
    return 1;
  end;

  procedure chase_move(
    p_session varchar2,p_actor actor_record,p_player_x number,p_player_y number,
    p_snapshot actor_snapshot
  ) is
    l_sx number:=sign(p_player_x-p_actor.x);
    l_sy number:=sign(p_player_y-p_actor.y);
    l_dx number_set;l_dy number_set;l_direction number_set;
    l_nx number;l_ny number;l_sector number;
  begin
    -- Stable preference is diagonal, horizontal, vertical, then no movement.
    l_dx(1):=l_sx;l_dy(1):=l_sy;l_direction(1):=case when l_sx=1 and l_sy=0 then 0 when l_sx=1 and l_sy=1 then 1 when l_sx=0 and l_sy=1 then 2 when l_sx=-1 and l_sy=1 then 3 when l_sx=-1 and l_sy=0 then 4 when l_sx=-1 and l_sy=-1 then 5 when l_sx=0 and l_sy=-1 then 6 else 7 end;
    l_dx(2):=l_sx;l_dy(2):=0;l_direction(2):=case when l_sx>=0 then 0 else 4 end;
    l_dx(3):=0;l_dy(3):=l_sy;l_direction(3):=case when l_sy>=0 then 2 else 6 end;
    for candidate in 1..3 loop
      if (l_dx(candidate)<>0 or l_dy(candidate)<>0)
         and collision_free(p_session,p_actor.mobj_id,p_actor.x,p_actor.y,
           p_actor.z,l_dx(candidate)*p_actor.speed,
           l_dy(candidate)*p_actor.speed,p_actor.radius,p_actor.height,
           p_snapshot)=1 then
        l_nx:=p_actor.x+l_dx(candidate)*p_actor.speed;
        l_ny:=p_actor.y+l_dy(candidate)*p_actor.speed;
        l_sector:=point_sector(l_nx,l_ny);
        update mobjs set x=l_nx,y=l_ny,sector_id=l_sector,
          move_direction=l_direction(candidate)
          where session_token=p_session and mobj_id=p_actor.mobj_id;
        return;
      end if;
    end loop;
    update mobjs set move_direction=-1
      where session_token=p_session and mobj_id=p_actor.mobj_id;
  end;

  procedure spawn_projectile(
    p_session varchar2,p_tic number,p_actor actor_record,
    p_player_x number,p_player_y number
  ) is
    l_id number;l_state varchar2(64);l_tics number;l_radius number;l_height number;
    l_kind varchar2(32);l_speed number;l_length number;l_mx number;l_my number;
  begin
    select coalesce(max(mobj_id),0)+1 into l_id from mobjs
      where session_token=p_session;
    select p.projectile_kind,p.speed,p.radius,p.height,p.spawn_state_id,s.tics
      into l_kind,l_speed,l_radius,l_height,l_state,l_tics
      from doom_projectile_def p join doom_state_def s
        on s.state_id=p.spawn_state_id
      where p.thing_type=p_actor.projectile_thing_type;
    l_length:=sqrt(power(p_player_x-p_actor.x,2)+power(p_player_y-p_actor.y,2));
    l_mx:=case when l_length=0 then 0 else (p_player_x-p_actor.x)*l_speed/l_length end;
    l_my:=case when l_length=0 then 0 else (p_player_y-p_actor.y)*l_speed/l_length end;
    insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,
      x,y,z,momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
      target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,
      owner_mobj_id,projectile_kind,exploded,sector_id)
    values(p_session,l_id,p_actor.projectile_thing_type,l_state,l_tics,
      p_actor.x,p_actor.y,p_actor.z+32,l_mx,l_my,0,0,l_radius,l_height,1,0,
      null,null,0,null,p_actor.mobj_id,l_kind,0,p_actor.sector_id);
    emit_event(p_session,p_tic,'MONSTER_PROJECTILE',p_actor.mobj_id,l_id,l_speed,l_kind);
  end;

  procedure create_drop(
    p_session varchar2,p_tic number,p_actor actor_record
  ) is
    l_id number;l_state varchar2(64);l_tics number;l_radius number;l_height number;
  begin
    if p_actor.drop_thing_type is null then return;end if;
    select coalesce(max(mobj_id),0)+1 into l_id from mobjs
      where session_token=p_session;
    select t.spawn_state_id,s.tics,coalesce(t.radius,8),coalesce(t.height,8)
      into l_state,l_tics,l_radius,l_height
      from doom_thing_type_def t join doom_state_def s
        on s.state_id=t.spawn_state_id
      where t.thing_type=p_actor.drop_thing_type;
    insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,
      x,y,z,momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
      target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,
      owner_mobj_id,projectile_kind,exploded,sector_id)
    values(p_session,l_id,p_actor.drop_thing_type,l_state,l_tics,
      p_actor.x,p_actor.y,p_actor.z,0,0,0,0,l_radius,l_height,1,0,
      null,null,0,null,p_actor.mobj_id,null,0,p_actor.sector_id);
    emit_event(p_session,p_tic,'MONSTER_DROP',p_actor.mobj_id,l_id,
               p_actor.drop_thing_type);
  end;

  procedure attack(
    p_session varchar2,p_tic number,p_actor actor_record,
    p_player_x number,p_player_y number,p_player_z number,p_player_sector number
  ) is
    l_distance number;l_damage number;l_spread number;l_miss number;
  begin
    l_distance:=sqrt(power(p_player_x-p_actor.x,2)+power(p_player_y-p_actor.y,2));
    if p_actor.attack_kind='MELEE' and l_distance>p_actor.melee_range then return;end if;
    if p_actor.visible=0 then return;end if;
    if p_actor.attack_kind='PROJECTILE' then
      spawn_projectile(p_session,p_tic,p_actor,p_player_x,p_player_y);
    elsif p_actor.attack_kind='HITSCAN' then
      -- Doom's former-human attack uses two ordered random reads for the BAM
      -- angle perturbation (one unit is 360/4096 degrees), followed by its
      -- damage read. Resolve that exact ray against the player's 16-unit
      -- radius; unobstructed line of sight is not a guaranteed ranged hit.
      l_spread:=(rng_draw(p_session)-rng_draw(p_session))*2*acos(-1)/4096;
      l_damage:=p_actor.damage_base*(1+mod(rng_draw(p_session),p_actor.damage_dice));
      l_miss:=abs(sin(l_spread)*l_distance);
      if l_miss<=16 then
        damage_player(p_session,p_tic,p_actor.mobj_id,l_damage);
      else
        emit_event(p_session,p_tic,'MONSTER_MISS',p_actor.mobj_id,null,
                   l_miss,to_char(l_spread,'TM9','NLS_NUMERIC_CHARACTERS=''.,'''));
      end if;
    else
      l_damage:=p_actor.damage_base*(1+mod(rng_draw(p_session),p_actor.damage_dice));
      damage_player(p_session,p_tic,p_actor.mobj_id,l_damage);
    end if;
  end;

  procedure advance(p_session_token in varchar2,p_tic in number) is
    l_actors actor_snapshot;l_count pls_integer:=0;l_player number;
    l_px number;l_py number;l_pz number;l_player_sector number;l_player_target number;
    l_sound number;l_seen_health number;l_roll number;l_next varchar2(64);
    l_next_tics number;l_action varchar2(64);l_distance number;l_state varchar2(64);
    l_visible number;l_wake number;
  begin
    select g.current_player_id,p.x,p.y,p.z
      into l_player,l_px,l_py,l_pz
      from game_sessions g join players p
        on p.session_token=g.session_token and p.player_id=g.current_player_id
      where g.session_token=p_session_token for update;
    l_player_sector:=point_sector(l_px,l_py);
    select max(mobj_id) into l_player_target from mobjs
      where session_token=p_session_token and mobj_id=l_player;
    l_sound:=player_made_sound(p_session_token,p_tic);

    -- Repair only legacy/null derived locations before the immutable actor
    -- snapshot.  The snapshot already used this same BSP result previously.
    update mobjs m set sector_id=(
      select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1
    ) where m.session_token=p_session_token and m.sector_id is null
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);

    -- Relational behavior and state graph are captured before any mutation.
    -- DOOM_MONSTER_DEF JOIN DOOM_STATE_DEF pins STATE_TICS/NEXT_STATE_ID.
    for row_ in (
      select m.mobj_id,m.thing_type,m.state_id,m.state_tics,m.x,m.y,m.z,
        m.radius,m.height,m.health,m.target_mobj_id,m.sector_id,
        m.move_direction,m.awake,m.attack_cooldown,m.monster_health_seen,
        m.death_processed,d.speed,d.pain_chance,d.melee_range,d.attack_kind,
        d.damage_base,d.damage_dice,d.projectile_thing_type,d.drop_thing_type,
        d.see_state_id,d.chase_state_id,d.melee_state_id,d.missile_state_id,
        d.pain_state_id,d.death_state_id,s.next_state_id,s.tics state_duration,
        coalesce(r.rejected,1) rejected,
        case when coalesce(r.rejected,1)=1 then 0
          when exists (
            select 1 from doom_block_cell bc
            join doom_block_line bl on bl.cell_id=bc.cell_id
            join doom_los_segment los on los.linedef_id=bl.linedef_id
            join doom_map_sector rs on rs.sector_id=los.right_sector_id
            left join sector_state rss on rss.session_token=p_session_token
              and rss.sector_id=rs.sector_id
            left join doom_map_sector ls on ls.sector_id=los.left_sector_id
            left join sector_state lss on lss.session_token=p_session_token
              and lss.sector_id=ls.sector_id
            where bc.world_min_x<=greatest(m.x,l_px)
              and bc.world_min_x+128>=least(m.x,l_px)
              and bc.world_min_y<=greatest(m.y,l_py)
              and bc.world_min_y+128>=least(m.y,l_py)
              and greatest(los.vx,los.vx+los.sx)>=least(m.x,l_px)
              and least(los.vx,los.vx+los.sx)<=greatest(m.x,l_px)
              and greatest(los.vy,los.vy+los.sy)>=least(m.y,l_py)
              and least(los.vy,los.vy+los.sy)<=greatest(m.y,l_py)
              and ((l_px-m.x)*los.sy-(l_py-m.y)*los.sx)<>0
              and ((los.vx-m.x)*los.sy-(los.vy-m.y)*los.sx) /
                  ((l_px-m.x)*los.sy-(l_py-m.y)*los.sx)>0
              and ((los.vx-m.x)*los.sy-(los.vy-m.y)*los.sx) /
                  ((l_px-m.x)*los.sy-(l_py-m.y)*los.sx)<1
              and ((los.vx-m.x)*(l_py-m.y)-(los.vy-m.y)*(l_px-m.x)) /
                  ((l_px-m.x)*los.sy-(l_py-m.y)*los.sx) between 0 and 1
              and (los.left_sector_id is null
                or least(coalesce(rss.ceiling_height,rs.ceiling_height),
                         coalesce(lss.ceiling_height,ls.ceiling_height))
                   <=greatest(coalesce(rss.floor_height,rs.floor_height),
                              coalesce(lss.floor_height,ls.floor_height)))
          ) then 0 else 1 end visible
      from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      join doom_state_def s on s.state_id=m.state_id
      left join doom_sector_reject r on r.source_sector_id=m.sector_id
        and r.target_sector_id=l_player_sector
      where m.session_token=p_session_token
      order by m.mobj_id
    ) loop
      l_count:=l_count+1;
      l_actors(l_count).mobj_id:=row_.mobj_id;l_actors(l_count).thing_type:=row_.thing_type;
      l_actors(l_count).state_id:=row_.state_id;l_actors(l_count).state_tics:=row_.state_tics;
      l_actors(l_count).x:=row_.x;l_actors(l_count).y:=row_.y;l_actors(l_count).z:=row_.z;
      l_actors(l_count).radius:=row_.radius;l_actors(l_count).height:=row_.height;
      l_actors(l_count).health:=row_.health;l_actors(l_count).target_mobj_id:=row_.target_mobj_id;
      l_actors(l_count).sector_id:=coalesce(row_.sector_id,point_sector(row_.x,row_.y));
      l_actors(l_count).move_direction:=row_.move_direction;l_actors(l_count).awake:=row_.awake;
      l_actors(l_count).attack_cooldown:=row_.attack_cooldown;
      l_actors(l_count).monster_health_seen:=row_.monster_health_seen;
      l_actors(l_count).death_processed:=row_.death_processed;
      l_actors(l_count).speed:=row_.speed;l_actors(l_count).pain_chance:=row_.pain_chance;
      l_actors(l_count).melee_range:=row_.melee_range;l_actors(l_count).attack_kind:=row_.attack_kind;
      l_actors(l_count).damage_base:=row_.damage_base;l_actors(l_count).damage_dice:=row_.damage_dice;
      l_actors(l_count).projectile_thing_type:=row_.projectile_thing_type;
      l_actors(l_count).drop_thing_type:=row_.drop_thing_type;
      l_actors(l_count).see_state_id:=row_.see_state_id;l_actors(l_count).chase_state_id:=row_.chase_state_id;
      l_actors(l_count).melee_state_id:=row_.melee_state_id;l_actors(l_count).missile_state_id:=row_.missile_state_id;
      l_actors(l_count).pain_state_id:=row_.pain_state_id;l_actors(l_count).death_state_id:=row_.death_state_id;
      l_actors(l_count).rejected:=case when row_.sector_id is null
        then reject_pair(l_actors(l_count).sector_id,l_player_sector)
        else row_.rejected end;
      l_actors(l_count).visible:=row_.visible;
    end loop;

    -- Apply common prior-tic housekeeping with one set operation. Sector IDs
    -- are maintained by CHASE_MOVE; only initial legacy/null rows need the
    -- bounded BSP location repair.
    update mobjs m set monster_health_seen=m.health,
      attack_cooldown=greatest(0,m.attack_cooldown-1)
      where m.session_token=p_session_token
        and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type)
        and (m.monster_health_seen is null or m.monster_health_seen<>m.health
          or m.attack_cooldown>0);

    for i in 1..l_count loop
      l_seen_health:=coalesce(l_actors(i).monster_health_seen,l_actors(i).health);
      if l_actors(i).health=0 then
        if l_actors(i).death_processed=0 then
          select tics into l_next_tics from doom_state_def
            where state_id=l_actors(i).death_state_id;
          update mobjs set state_id=l_actors(i).death_state_id,
            state_tics=l_next_tics,death_processed=1,awake=0,flags=0,
            target_mobj_id=null,move_direction=-1
            where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
          update players set kill_count=kill_count+1
            where session_token=p_session_token and player_id=l_player;
          emit_event(p_session_token,p_tic,'MONSTER_DEATH',l_actors(i).mobj_id);
          create_drop(p_session_token,p_tic,l_actors(i));
        elsif l_actors(i).state_tics>0 then
          if l_actors(i).state_tics-1>0 then
            update mobjs set state_tics=state_tics-1
              where session_token=p_session_token
                and mobj_id=l_actors(i).mobj_id;
          else
            select next_state_id into l_next from doom_state_def
              where state_id=l_actors(i).state_id;
            select tics into l_next_tics from doom_state_def
              where state_id=l_next;
            update mobjs set state_id=l_next,state_tics=l_next_tics
              where session_token=p_session_token
                and mobj_id=l_actors(i).mobj_id;
          end if;
        end if;
        continue;
      end if;

      if l_actors(i).health<l_seen_health then
        l_roll:=rng_draw(p_session_token);
        if l_roll<l_actors(i).pain_chance then
          select tics into l_next_tics from doom_state_def
            where state_id=l_actors(i).pain_state_id;
          update mobjs set state_id=l_actors(i).pain_state_id,
            state_tics=l_next_tics,awake=1
            where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
          emit_event(p_session_token,p_tic,'MONSTER_PAIN',l_actors(i).mobj_id,
                     l_player_target,l_roll);
          continue;
        end if;
      end if;

      l_wake:=0;l_visible:=l_actors(i).visible;
      if l_actors(i).awake=0 then
        if l_sound=1 and sound_reach(l_player_sector,l_actors(i).sector_id)=1 then
          l_wake:=1;
        else
          l_wake:=l_visible;
        end if;
      end if;
      if l_actors(i).awake=0 and l_wake=1 then
        select tics into l_next_tics from doom_state_def
          where state_id=l_actors(i).see_state_id;
        update mobjs set awake=1,target_mobj_id=l_player_target,
          state_id=l_actors(i).see_state_id,state_tics=l_next_tics
          where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
        emit_event(p_session_token,p_tic,'MONSTER_WAKE',l_actors(i).mobj_id,
          l_player_target,null,case when l_visible=1 then 'SEEN' else 'HEARD' end);
        continue;
      elsif l_actors(i).awake=0 then
        continue;
      end if;

      l_state:=l_actors(i).state_id;
      if l_actors(i).state_tics>0 then
        update mobjs set state_tics=state_tics-1
          where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
        if l_actors(i).state_tics-1>0 then continue;end if;
        select next_state_id into l_next from doom_state_def
          where state_id=l_actors(i).state_id;
        select tics,action_name into l_next_tics,l_action from doom_state_def
          where state_id=l_next;
        update mobjs set state_id=l_next,state_tics=l_next_tics
          where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
        l_state:=l_next;
      else
        select action_name into l_action from doom_state_def where state_id=l_state;
      end if;

      if l_action='CHASE' then
        l_distance:=sqrt(power(l_px-l_actors(i).x,2)+power(l_py-l_actors(i).y,2));
        if l_actors(i).attack_cooldown=0 and
           ((l_actors(i).attack_kind='MELEE' and l_distance<=l_actors(i).melee_range)
            or l_actors(i).attack_kind in('HITSCAN','PROJECTILE')) then
          l_state:=case when l_actors(i).attack_kind='MELEE'
            then l_actors(i).melee_state_id else l_actors(i).missile_state_id end;
          select tics into l_next_tics from doom_state_def where state_id=l_state;
          update mobjs set state_id=l_state,state_tics=l_next_tics,
            attack_cooldown=l_next_tics
            where session_token=p_session_token and mobj_id=l_actors(i).mobj_id;
          attack(p_session_token,p_tic,l_actors(i),l_px,l_py,l_pz,l_player_sector);
        else
          chase_move(p_session_token,l_actors(i),l_px,l_py,l_actors);
        end if;
      elsif l_action in('MELEE','HITSCAN','PROJECTILE') then
        attack(p_session_token,p_tic,l_actors(i),l_px,l_py,l_pz,l_player_sector);
      end if;
    end loop;
  end;
end doom_monsters;
/
