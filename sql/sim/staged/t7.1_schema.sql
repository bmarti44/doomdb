-- T7.1 staged schema migration.  Apply after T6.4 and before
-- 050_combat_inventory.sql during ordered integration.
create table doom_ammo_def (
  ammo_type varchar2(32) not null,
  normal_cap number(10) not null,
  backpack_cap number(10) not null,
  constraint doom_ammo_def_pk primary key (ammo_type),
  constraint doom_ammo_def_cap_ck check (
    normal_cap > 0 and backpack_cap >= normal_cap
  )
);

create table doom_projectile_def (
  projectile_kind varchar2(32) not null,
  thing_type number(10) not null,
  speed number not null,
  radius number not null,
  height number not null,
  damage number(10) not null,
  splash_radius number not null,
  splash_damage number(10) not null,
  spawn_state_id varchar2(64) not null,
  constraint doom_projectile_def_pk primary key (projectile_kind),
  constraint doom_projectile_def_type_uq unique (thing_type),
  constraint doom_projectile_def_num_ck check (
    speed > 0 and radius > 0 and height > 0 and damage > 0
    and splash_radius >= 0 and splash_damage >= 0
  ),
  constraint doom_projectile_def_type_fk foreign key (thing_type)
    references doom_thing_type_def (thing_type),
  constraint doom_projectile_def_state_fk foreign key (spawn_state_id)
    references doom_state_def (state_id)
);

alter table doom_weapon_def add (
  ammo_cost number(10) default 0 not null,
  attack_kind varchar2(16) default 'MELEE' not null,
  pellet_count number(3) default 1 not null,
  damage_multiplier number(3) default 3 not null,
  spread_scale number default 0 not null,
  projectile_kind varchar2(32),
  constraint doom_weapon_def_attack_ck check (
    attack_kind in ('MELEE','HITSCAN','PROJECTILE')
    and ammo_cost >= 0 and pellet_count > 0
    and damage_multiplier > 0 and spread_scale >= 0
  ),
  constraint doom_weapon_def_projectile_fk foreign key (projectile_kind)
    references doom_projectile_def (projectile_kind)
);

alter table doom_pickup_def add (
  ammo_type varchar2(32),
  health_amount number(10),
  health_cap number(10),
  health_minimum number(10),
  armor_amount number(10),
  armor_cap number(10),
  armor_set number(10),
  armor_type number(1),
  grants_power varchar2(32),
  grants_backpack number(1) default 0 not null,
  constraint doom_pickup_def_ammo_fk foreign key (ammo_type)
    references doom_ammo_def (ammo_type),
  constraint doom_pickup_def_grant_ck check (
    (health_amount is null or health_amount >= 0)
    and (health_cap is null or health_cap >= 0)
    and (health_minimum is null or health_minimum >= 0)
    and (armor_amount is null or armor_amount >= 0)
    and (armor_cap is null or armor_cap >= 0)
    and (armor_set is null or armor_set >= 0)
    and (armor_type is null or armor_type between 0 and 2)
    and grants_backpack in (0,1)
  )
);

alter table players add (
  pending_weapon varchar2(32),
  weapon_state varchar2(64) default 'WEAPON_PISTOL_READY' not null,
  weapon_state_tics number(10) default 0 not null,
  flash_state varchar2(64),
  flash_state_tics number(10) default 0 not null,
  refire number(10) default 0 not null,
  backpack number(1) default 0 not null,
  power_berserk number(1) default 0 not null,
  constraint players_pending_weapon_fk foreign key (pending_weapon)
    references doom_weapon_def (weapon_id),
  constraint players_weapon_state_fk foreign key (weapon_state)
    references doom_state_def (state_id),
  constraint players_flash_state_fk foreign key (flash_state)
    references doom_state_def (state_id),
  constraint players_combat_num_ck check (
    weapon_state_tics >= 0 and flash_state_tics >= 0 and refire >= 0
    and backpack in (0,1) and power_berserk in (0,1)
  )
);

alter table mobjs add (
  owner_mobj_id number(12),
  projectile_kind varchar2(32),
  exploded number(1) default 0 not null,
  constraint mobjs_owner_fk foreign key (session_token,owner_mobj_id)
    references mobjs (session_token,mobj_id) deferrable initially deferred,
  constraint mobjs_projectile_fk foreign key (projectile_kind)
    references doom_projectile_def (projectile_kind),
  constraint mobjs_exploded_ck check (exploded in (0,1))
);
