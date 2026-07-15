-- T7.1 reviewed relational combat definitions.
insert all
  into doom_ammo_def(ammo_type,normal_cap,backpack_cap) values('BULLET',200,400)
  into doom_ammo_def(ammo_type,normal_cap,backpack_cap) values('SHELL',50,100)
  into doom_ammo_def(ammo_type,normal_cap,backpack_cap) values('ROCKET',50,100)
  into doom_ammo_def(ammo_type,normal_cap,backpack_cap) values('CELL',300,600)
select 1 from dual;

insert all
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_FIST_LOWER',3,'WEAPON_FIST_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_FIST_RAISE',3,'WEAPON_FIST_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_PISTOL_LOWER',3,'WEAPON_PISTOL_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_PISTOL_RAISE',3,'WEAPON_PISTOL_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_SHOTGUN_LOWER',3,'WEAPON_SHOTGUN_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_SHOTGUN_RAISE',3,'WEAPON_SHOTGUN_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_CHAINGUN_LOWER',3,'WEAPON_CHAINGUN_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_CHAINGUN_RAISE',3,'WEAPON_CHAINGUN_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_ROCKET_LAUNCHER_LOWER',3,'WEAPON_ROCKET_LAUNCHER_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_ROCKET_LAUNCHER_RAISE',3,'WEAPON_ROCKET_LAUNCHER_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_PLASMA_RIFLE_LOWER',3,'WEAPON_PLASMA_RIFLE_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_PLASMA_RIFLE_RAISE',3,'WEAPON_PLASMA_RIFLE_READY','WEAPON_RAISE')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_CHAINSAW_LOWER',3,'WEAPON_CHAINSAW_RAISE','WEAPON_LOWER')
  into doom_state_def(state_id,tics,next_state_id,action_name) values('WEAPON_CHAINSAW_RAISE',3,'WEAPON_CHAINSAW_READY','WEAPON_RAISE')
select 1 from dual;

insert all
  into doom_state_def(state_id,tics,next_state_id,action_name,sprite_prefix,sprite_frame,rotations)
    values('PROJECTILE_ROCKET_FLY',1,'PROJECTILE_ROCKET_FLY','PROJECTILE_FLY','MISL','A','0')
  into doom_state_def(state_id,tics,next_state_id,action_name,sprite_prefix,sprite_frame,rotations)
    values('PROJECTILE_PLASMA_FLY',1,'PROJECTILE_PLASMA_FLY','PROJECTILE_FLY','PLSS','A','0')
select 1 from dual;

insert all
  into doom_thing_type_def(thing_type,type_name,category,spawn_state_id,radius,height,spawn_health,flags)
    values(9001,'PLAYER_ROCKET_PROJECTILE','projectile','PROJECTILE_ROCKET_FLY',11,8,1,0)
  into doom_thing_type_def(thing_type,type_name,category,spawn_state_id,radius,height,spawn_health,flags)
    values(9002,'PLAYER_PLASMA_PROJECTILE','projectile','PROJECTILE_PLASMA_FLY',13,8,1,0)
select 1 from dual;

insert all
  into doom_projectile_def(projectile_kind,thing_type,speed,radius,height,damage,splash_radius,splash_damage,spawn_state_id)
    values('ROCKET',9001,20,11,8,20,128,128,'PROJECTILE_ROCKET_FLY')
  into doom_projectile_def(projectile_kind,thing_type,speed,radius,height,damage,splash_radius,splash_damage,spawn_state_id)
    values('PLASMA',9002,25,13,8,20,0,0,'PROJECTILE_PLASMA_FLY')
select 1 from dual;

update doom_weapon_def set ammo_cost=0,attack_kind='MELEE',pellet_count=1,
  damage_multiplier=3,spread_scale=0,projectile_kind=null where weapon_id='FIST';
update doom_weapon_def set ammo_cost=1,attack_kind='HITSCAN',pellet_count=1,
  damage_multiplier=3,spread_scale=0.0003834951969714103,projectile_kind=null where weapon_id='PISTOL';
update doom_weapon_def set ammo_cost=1,attack_kind='HITSCAN',pellet_count=7,
  damage_multiplier=5,spread_scale=0.0003834951969714103,projectile_kind=null where weapon_id='SHOTGUN';
update doom_weapon_def set ammo_cost=1,attack_kind='HITSCAN',pellet_count=1,
  damage_multiplier=3,spread_scale=0.0003834951969714103,projectile_kind=null where weapon_id='CHAINGUN';
update doom_weapon_def set ammo_cost=1,attack_kind='PROJECTILE',pellet_count=1,
  damage_multiplier=1,spread_scale=0,projectile_kind='ROCKET' where weapon_id='ROCKET_LAUNCHER';
update doom_weapon_def set ammo_cost=1,attack_kind='PROJECTILE',pellet_count=1,
  damage_multiplier=1,spread_scale=0,projectile_kind='PLASMA' where weapon_id='PLASMA_RIFLE';
update doom_weapon_def set ammo_cost=0,attack_kind='MELEE',pellet_count=1,
  damage_multiplier=3,spread_scale=0,projectile_kind=null where weapon_id='CHAINSAW';

-- Replace the early behavior labels with exact, relational grants.  Weapon
-- pickups are inserted here because the earlier closure seed only held the 17
-- non-weapon pickup rows.
delete from doom_pickup_def;
insert all
  into doom_pickup_def(thing_type,pickup_kind,grants_key,grants_backpack) values(5,'KEY','BLUE',0)
  into doom_pickup_def(thing_type,pickup_kind,grants_backpack) values(8,'BACKPACK',1)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount,grants_weapon_id) values(2001,'WEAPON','SHELL',8,'SHOTGUN')
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount,grants_weapon_id) values(2002,'WEAPON','BULLET',20,'CHAINGUN')
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount,grants_weapon_id) values(2003,'WEAPON','ROCKET',2,'ROCKET_LAUNCHER')
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount,grants_weapon_id) values(2004,'WEAPON','CELL',40,'PLASMA_RIFLE')
  into doom_pickup_def(thing_type,pickup_kind,grants_weapon_id) values(2005,'WEAPON','CHAINSAW')
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2007,'AMMO','BULLET',10)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2008,'AMMO','SHELL',20)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2010,'AMMO','ROCKET',5)
  into doom_pickup_def(thing_type,pickup_kind,health_amount,health_cap) values(2011,'HEALTH',10,100)
  into doom_pickup_def(thing_type,pickup_kind,health_amount,health_cap) values(2012,'HEALTH',25,100)
  into doom_pickup_def(thing_type,pickup_kind,health_amount,health_cap) values(2013,'HEALTH',100,200)
  into doom_pickup_def(thing_type,pickup_kind,health_amount,health_cap) values(2014,'HEALTH',1,200)
  into doom_pickup_def(thing_type,pickup_kind,armor_amount,armor_cap) values(2015,'ARMOR',1,200)
  into doom_pickup_def(thing_type,pickup_kind,armor_set,armor_type) values(2018,'ARMOR_SET',100,1)
  into doom_pickup_def(thing_type,pickup_kind,armor_set,armor_type) values(2019,'ARMOR_SET',200,2)
  into doom_pickup_def(thing_type,pickup_kind,health_minimum,grants_power) values(2023,'POWER',100,'BERSERK')
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2046,'AMMO','ROCKET',1)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2047,'AMMO','CELL',20)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2048,'AMMO','BULLET',50)
  into doom_pickup_def(thing_type,pickup_kind,ammo_type,amount) values(2049,'AMMO','CELL',100)
select 1 from dual;
