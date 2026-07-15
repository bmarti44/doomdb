-- T7.3 audio schema migration. It precedes the T6.4 history installation so
-- history hashes are authored directly against the final asset provenance.
create table doom_audio_event_def (
  event_type varchar2(32) not null,
  event_class number(10) not null,
  asset_kind varchar2(20) not null,
  asset_name varchar2(32) not null,
  volume number(3) not null,
  separation number(3) not null,
  constraint doom_audio_event_def_pk primary key (event_type),
  constraint doom_audio_event_def_asset_fk foreign key (asset_kind,asset_name)
    references doom_asset (asset_kind,asset_name),
  constraint doom_audio_event_def_class_ck check (event_class >= 0),
  constraint doom_audio_event_def_mix_ck check (
    volume between 0 and 255 and separation between 0 and 255)
);

alter table audio_events drop constraint audio_events_sound_fk;
alter table audio_events add (
  asset_kind varchar2(20) not null,
  asset_name varchar2(32) not null,
  constraint audio_events_asset_fk foreign key (asset_kind,asset_name)
    references doom_asset (asset_kind,asset_name)
);
alter table audio_events drop column sound_id;
