-- T7.2 independently authored state graph and relational monster matrix.
-- State identifiers are type-specific so no procedural type dispatch is needed.
set constraints all deferred;

insert all
  into doom_state_def values('MON_SERGEANT_IDLE',10,'MON_SERGEANT_IDLE','LOOK','SPOS','A','12345678')
  into doom_state_def values('MON_SERGEANT_SEE',3,'MON_SERGEANT_CHASE','SEE','SPOS','A','12345678')
  into doom_state_def values('MON_SERGEANT_CHASE',3,'MON_SERGEANT_CHASE','CHASE','SPOS','B','12345678')
  into doom_state_def values('MON_SERGEANT_MELEE',4,'MON_SERGEANT_CHASE','HITSCAN','SPOS','E','12345678')
  into doom_state_def values('MON_SERGEANT_MISSILE',4,'MON_SERGEANT_CHASE','HITSCAN','SPOS','E','12345678')
  into doom_state_def values('MON_SERGEANT_PAIN',2,'MON_SERGEANT_CHASE','PAIN','SPOS','G','12345678')
  into doom_state_def values('MON_SERGEANT_DEATH',5,'MON_SERGEANT_CORPSE','DEATH','SPOS','L','0')
  into doom_state_def values('MON_SERGEANT_CORPSE',-1,'MON_SERGEANT_CORPSE','NONE','SPOS','N','0')
  into doom_state_def values('MON_SPECTRE_IDLE',10,'MON_SPECTRE_IDLE','LOOK','SARG','A','12345678')
  into doom_state_def values('MON_SPECTRE_SEE',3,'MON_SPECTRE_CHASE','SEE','SARG','A','12345678')
  into doom_state_def values('MON_SPECTRE_CHASE',3,'MON_SPECTRE_CHASE','CHASE','SARG','B','12345678')
  into doom_state_def values('MON_SPECTRE_MELEE',4,'MON_SPECTRE_CHASE','MELEE','SARG','E','12345678')
  into doom_state_def values('MON_SPECTRE_MISSILE',4,'MON_SPECTRE_CHASE','MELEE','SARG','E','12345678')
  into doom_state_def values('MON_SPECTRE_PAIN',2,'MON_SPECTRE_CHASE','PAIN','SARG','F','12345678')
  into doom_state_def values('MON_SPECTRE_DEATH',5,'MON_SPECTRE_CORPSE','DEATH','SARG','J','0')
  into doom_state_def values('MON_SPECTRE_CORPSE',-1,'MON_SPECTRE_CORPSE','NONE','SARG','N','0')
  into doom_state_def values('MON_IMP_IDLE',10,'MON_IMP_IDLE','LOOK','TROO','A','12345678')
  into doom_state_def values('MON_IMP_SEE',3,'MON_IMP_CHASE','SEE','TROO','A','12345678')
  into doom_state_def values('MON_IMP_CHASE',3,'MON_IMP_CHASE','CHASE','TROO','B','12345678')
  into doom_state_def values('MON_IMP_MELEE',4,'MON_IMP_CHASE','MELEE','TROO','G','12345678')
  into doom_state_def values('MON_IMP_MISSILE',6,'MON_IMP_CHASE','PROJECTILE','TROO','E','12345678')
  into doom_state_def values('MON_IMP_PAIN',2,'MON_IMP_CHASE','PAIN','TROO','H','12345678')
  into doom_state_def values('MON_IMP_DEATH',5,'MON_IMP_CORPSE','DEATH','TROO','M','0')
  into doom_state_def values('MON_IMP_CORPSE',-1,'MON_IMP_CORPSE','NONE','TROO','N','0')
  into doom_state_def values('MON_DEMON_IDLE',10,'MON_DEMON_IDLE','LOOK','SARG','A','12345678')
  into doom_state_def values('MON_DEMON_SEE',3,'MON_DEMON_CHASE','SEE','SARG','A','12345678')
  into doom_state_def values('MON_DEMON_CHASE',3,'MON_DEMON_CHASE','CHASE','SARG','B','12345678')
  into doom_state_def values('MON_DEMON_MELEE',4,'MON_DEMON_CHASE','MELEE','SARG','E','12345678')
  into doom_state_def values('MON_DEMON_MISSILE',4,'MON_DEMON_CHASE','MELEE','SARG','E','12345678')
  into doom_state_def values('MON_DEMON_PAIN',2,'MON_DEMON_CHASE','PAIN','SARG','F','12345678')
  into doom_state_def values('MON_DEMON_DEATH',5,'MON_DEMON_CORPSE','DEATH','SARG','J','0')
  into doom_state_def values('MON_DEMON_CORPSE',-1,'MON_DEMON_CORPSE','NONE','SARG','N','0')
  into doom_state_def values('MON_ZOMBIE_IDLE',10,'MON_ZOMBIE_IDLE','LOOK','POSS','A','12345678')
  into doom_state_def values('MON_ZOMBIE_SEE',3,'MON_ZOMBIE_CHASE','SEE','POSS','A','12345678')
  into doom_state_def values('MON_ZOMBIE_CHASE',3,'MON_ZOMBIE_CHASE','CHASE','POSS','B','12345678')
  into doom_state_def values('MON_ZOMBIE_MELEE',4,'MON_ZOMBIE_CHASE','HITSCAN','POSS','E','12345678')
  into doom_state_def values('MON_ZOMBIE_MISSILE',4,'MON_ZOMBIE_CHASE','HITSCAN','POSS','E','12345678')
  into doom_state_def values('MON_ZOMBIE_PAIN',2,'MON_ZOMBIE_CHASE','PAIN','POSS','G','12345678')
  into doom_state_def values('MON_ZOMBIE_DEATH',5,'MON_ZOMBIE_CORPSE','DEATH','POSS','L','0')
  into doom_state_def values('MON_ZOMBIE_CORPSE',-1,'MON_ZOMBIE_CORPSE','NONE','POSS','N','0')
select 1 from dual;

insert into doom_state_def values(
  'MON_IMP_FIREBALL_FLY',1,'MON_IMP_FIREBALL_FLY','PROJECTILE_FLY','BAL1','A','0');

insert into doom_thing_type_def(
  thing_type,type_name,category,spawn_state_id,radius,height,spawn_health,flags)
values(9100,'IMP_FIREBALL','projectile','MON_IMP_FIREBALL_FLY',6,8,1,0);

insert into doom_projectile_def(
  projectile_kind,thing_type,speed,radius,height,damage,splash_radius,
  splash_damage,spawn_state_id)
values('IMP_FIREBALL',9100,10,6,8,3,0,0,'MON_IMP_FIREBALL_FLY');

insert all
  into doom_monster_def values(9,8,170,64,'HITSCAN',3,5,null,2001,'MON_SERGEANT_SEE','MON_SERGEANT_CHASE','MON_SERGEANT_MELEE','MON_SERGEANT_MISSILE','MON_SERGEANT_PAIN','MON_SERGEANT_DEATH')
  into doom_monster_def values(58,8,180,64,'MELEE',4,10,null,null,'MON_SPECTRE_SEE','MON_SPECTRE_CHASE','MON_SPECTRE_MELEE','MON_SPECTRE_MISSILE','MON_SPECTRE_PAIN','MON_SPECTRE_DEATH')
  into doom_monster_def values(3001,8,200,64,'PROJECTILE',3,8,9100,null,'MON_IMP_SEE','MON_IMP_CHASE','MON_IMP_MELEE','MON_IMP_MISSILE','MON_IMP_PAIN','MON_IMP_DEATH')
  into doom_monster_def values(3002,10,180,64,'MELEE',4,10,null,null,'MON_DEMON_SEE','MON_DEMON_CHASE','MON_DEMON_MELEE','MON_DEMON_MISSILE','MON_DEMON_PAIN','MON_DEMON_DEATH')
  into doom_monster_def values(3004,8,200,64,'HITSCAN',3,5,null,2007,'MON_ZOMBIE_SEE','MON_ZOMBIE_CHASE','MON_ZOMBIE_MELEE','MON_ZOMBIE_MISSILE','MON_ZOMBIE_PAIN','MON_ZOMBIE_DEATH')
select 1 from dual;

update doom_thing_type_def t set
  (spawn_state_id,radius,height)=
  (select case d.thing_type
      when 9 then 'MON_SERGEANT_IDLE'
      when 58 then 'MON_SPECTRE_IDLE'
      when 3001 then 'MON_IMP_IDLE'
      when 3002 then 'MON_DEMON_IDLE'
      else 'MON_ZOMBIE_IDLE' end,20,56
     from doom_monster_def d where d.thing_type=t.thing_type)
where exists(select 1 from doom_monster_def d where d.thing_type=t.thing_type);

set constraints all immediate;

