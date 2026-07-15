create table doom_engine_source (
  source_id varchar2(64) not null,
  title varchar2(200) not null,
  source_url varchar2(1000),
  license_name varchar2(100),
  constraint doom_engine_source_pk primary key (source_id)
);

create table doom_linedef_special_def (
  special_id number(10) not null,
  semantics varchar2(1000) not null,
  constraint doom_linedef_special_def_pk primary key (special_id),
  constraint doom_linedef_special_id_ck check (special_id >= 0)
);

create table doom_sector_special_def (
  special_id number(10) not null,
  semantics varchar2(1000) not null,
  constraint doom_sector_special_def_pk primary key (special_id),
  constraint doom_sector_special_id_ck check (special_id >= 0)
);

create table doom_state_def (
  state_id varchar2(64) not null,
  tics number(10) not null,
  next_state_id varchar2(64),
  action_name varchar2(64) not null,
  sprite_prefix varchar2(8),
  sprite_frame varchar2(2),
  rotations varchar2(16),
  constraint doom_state_def_pk primary key (state_id),
  constraint doom_state_tics_ck check (tics >= -1),
  constraint doom_state_next_fk foreign key (next_state_id) references doom_state_def (state_id)
    deferrable initially deferred
);

create table doom_thing_type_def (
  thing_type number(10) not null,
  type_name varchar2(64) not null,
  category varchar2(32) not null,
  spawn_state_id varchar2(64),
  radius number(10),
  height number(10),
  spawn_health number(10),
  flags number(10) default 0 not null,
  constraint doom_thing_type_def_pk primary key (thing_type),
  constraint doom_thing_type_name_uq unique (type_name),
  constraint doom_thing_type_id_ck check (thing_type > 0),
  constraint doom_thing_type_size_ck check ((radius is null or radius >= 0) and (height is null or height >= 0)),
  constraint doom_thing_type_health_ck check (spawn_health is null or spawn_health >= 0),
  constraint doom_thing_type_state_fk foreign key (spawn_state_id) references doom_state_def (state_id)
);

create table doom_weapon_def (
  weapon_id varchar2(32) not null,
  slot_number number(2) not null,
  thing_type number(10),
  ammo_type varchar2(32) not null,
  ready_state_id varchar2(64) not null,
  fire_state_id varchar2(64) not null,
  refire_state_id varchar2(64) not null,
  flash_state_id varchar2(64) not null,
  constraint doom_weapon_def_pk primary key (weapon_id),
  constraint doom_weapon_slot_uq unique (slot_number),
  constraint doom_weapon_slot_ck check (slot_number between 1 and 9),
  constraint doom_weapon_thing_fk foreign key (thing_type) references doom_thing_type_def (thing_type),
  constraint doom_weapon_ready_fk foreign key (ready_state_id) references doom_state_def (state_id),
  constraint doom_weapon_fire_fk foreign key (fire_state_id) references doom_state_def (state_id),
  constraint doom_weapon_refire_fk foreign key (refire_state_id) references doom_state_def (state_id),
  constraint doom_weapon_flash_fk foreign key (flash_state_id) references doom_state_def (state_id)
);

create table doom_pickup_def (
  thing_type number(10) not null,
  pickup_kind varchar2(32) not null,
  amount number(10),
  cap number(10),
  grants_weapon_id varchar2(32),
  grants_key varchar2(16),
  constraint doom_pickup_def_pk primary key (thing_type),
  constraint doom_pickup_type_fk foreign key (thing_type) references doom_thing_type_def (thing_type),
  constraint doom_pickup_weapon_fk foreign key (grants_weapon_id) references doom_weapon_def (weapon_id),
  constraint doom_pickup_amount_ck check ((amount is null or amount >= 0) and (cap is null or cap >= 0))
);

create table doom_rng_value (
  rng_index number(3) not null,
  rng_value number(3) not null,
  constraint doom_rng_value_pk primary key (rng_index),
  constraint doom_rng_index_ck check (rng_index between 0 and 255),
  constraint doom_rng_value_ck check (rng_value between 0 and 255)
);

alter table doom_sprite_rotation add constraint doom_sprite_rotation_state_fk
  foreign key (state_id) references doom_state_def (state_id);
