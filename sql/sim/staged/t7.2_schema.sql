-- T7.2 staged schema migration. Apply after the accepted T7.1 migration and
-- before 060_monsters.sql during ordered integration.
create table doom_monster_def (
  thing_type number(10) not null,
  speed number not null,
  pain_chance number(3) not null,
  melee_range number not null,
  attack_kind varchar2(16) not null,
  damage_base number(10) not null,
  damage_dice number(10) not null,
  projectile_thing_type number(10),
  drop_thing_type number(10),
  see_state_id varchar2(64) not null,
  chase_state_id varchar2(64) not null,
  melee_state_id varchar2(64) not null,
  missile_state_id varchar2(64) not null,
  pain_state_id varchar2(64) not null,
  death_state_id varchar2(64) not null,
  constraint doom_monster_def_pk primary key (thing_type),
  constraint doom_monster_def_type_fk foreign key (thing_type)
    references doom_thing_type_def (thing_type),
  constraint doom_monster_def_projectile_fk foreign key (projectile_thing_type)
    references doom_thing_type_def (thing_type),
  constraint doom_monster_def_drop_fk foreign key (drop_thing_type)
    references doom_thing_type_def (thing_type),
  constraint doom_monster_def_see_fk foreign key (see_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_chase_fk foreign key (chase_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_melee_fk foreign key (melee_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_missile_fk foreign key (missile_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_pain_fk foreign key (pain_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_death_fk foreign key (death_state_id)
    references doom_state_def (state_id),
  constraint doom_monster_def_behavior_ck check (
    speed > 0 and pain_chance between 0 and 255 and melee_range > 0
    and attack_kind in ('MELEE','HITSCAN','PROJECTILE')
    and damage_base > 0 and damage_dice > 0
    and (attack_kind <> 'PROJECTILE' or projectile_thing_type is not null)
  )
);

alter table mobjs add (
  sector_id number(10),
  move_direction number(2) default -1 not null,
  awake number(1) default 0 not null,
  attack_cooldown number(10) default 0 not null,
  monster_health_seen number(10),
  death_processed number(1) default 0 not null,
  constraint mobjs_monster_sector_fk foreign key (sector_id)
    references doom_map_sector (sector_id),
  constraint mobjs_monster_runtime_ck check (
    move_direction between -1 and 7 and awake in (0,1)
    and attack_cooldown >= 0 and death_processed in (0,1)
    and (monster_health_seen is null or monster_health_seen >= 0)
  )
);

