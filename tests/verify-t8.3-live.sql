whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  session_ varchar2(32);payload_ blob;owner_ number;projectile_ number;
  x_ number;y_ number;sector_ number;owner_health_ number;player_health_ number;
  damage_tic_ number;missing_ number;fire_assets_ number;travelled_ number;impact_ number;
begin
  select count(*) into missing_ from doom_state_def state
  where state.sprite_prefix is not null and state.sprite_frame is not null
    and (state.state_id like 'MON\_%' escape '\' or state.state_id like 'THING\_%' escape '\')
    and not exists(select 1 from doom_r2_world_sprite_catalog catalog
      where catalog.state_id=state.state_id);
  if missing_<>0 then raise_application_error(-20000,
    'renderable monster states missing from catalog: '||missing_);end if;

  select count(distinct catalog.asset_id) into fire_assets_
  from doom_state_def state join doom_r2_world_sprite_catalog catalog
    on catalog.state_id=state.state_id and catalog.rotation_no=0
  where state.state_id in('WEAPON_PISTOL_READY','WEAPON_PISTOL_FIRE');
  if fire_assets_<>2 then raise_application_error(-20000,
    'pistol ready/fire states do not resolve to distinct authored assets');end if;

  doom_api.new_game(3,session_,payload_);
  select p.x,p.y into x_,y_ from players p join game_sessions s
    on s.session_token=p.session_token and s.current_player_id=p.player_id
    where p.session_token=session_;
  select sector_id into sector_ from table(doom_bsp_locate(x_,y_)) where rownum=1;
  delete from mobjs where session_token=session_ and projectile_kind is not null;
  update mobjs set health=0 where session_token=session_ and thing_type in
    (select thing_type from doom_monster_def);
  select min(mobj_id) into owner_ from mobjs where session_token=session_ and thing_type=3001;
  update mobjs set x=x_+64,y=y_,sector_id=sector_,health=60,
    monster_health_seen=60,death_processed=0,awake=1
    where session_token=session_ and mobj_id=owner_;
  select coalesce(max(mobj_id),0)+1 into projectile_ from mobjs where session_token=session_;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
    projectile_kind,exploded,sector_id)
  select session_,projectile_,d.thing_type,d.spawn_state_id,1,x_+64,y_,32,
    -10,0,0,180,d.radius,d.height,1,0,null,null,0,null,owner_,d.projectile_kind,0,sector_
  from doom_projectile_def d where d.projectile_kind='IMP_FIREBALL';

  doom_combat.advance_projectiles(session_,1);
  select health into owner_health_ from mobjs where session_token=session_ and mobj_id=owner_;
  select count(*) into travelled_ from mobjs
    where session_token=session_ and mobj_id=projectile_ and x=x_+54;
  if owner_health_<>60 or travelled_<>1 then
    raise_application_error(-20000,'projectile collided with its owner instead of travelling');
  end if;
  for tic_ in 2..8 loop
    doom_combat.advance_projectiles(session_,tic_);
  end loop;
  select health into player_health_ from players where session_token=session_ and
    player_id=(select current_player_id from game_sessions where session_token=session_);
  select min(tic) into damage_tic_ from game_events where session_token=session_
    and event_type='PLAYER_DAMAGE' and actor_mobj_id=projectile_;
  select count(*) into impact_ from game_events
    where session_token=session_ and tic=damage_tic_ and event_type='PROJECTILE_IMPACT'
      and actor_mobj_id=projectile_;
  if player_health_>=100 or damage_tic_ is null or impact_<>1 then
    raise_application_error(-20000,'player damage lacks a correlated projectile impact');
  end if;
  dbms_output.put_line('PASS T8.3-LIVE-SQL catalog=complete weapon_assets=2 owner_health='||
    owner_health_||' player_health='||player_health_||' damage_tic='||damage_tic_);
  delete from game_sessions where session_token=session_;commit;
exception when others then
  rollback;
  if session_ is not null then delete from game_sessions where session_token=session_;commit;end if;
  raise;
end;
/
