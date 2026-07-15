-- T7.3 reviewed, relational transition-to-asset definitions. Event classes
-- are stable logical ordering groups, independent of insertion order.
insert all
  into doom_audio_event_def values('MAP_START',0,'music','D_E1M1',255,128)
  into doom_audio_event_def values('WEAPON_PISTOL_FIRE',10,'sound','DSPISTOL',255,128)
  into doom_audio_event_def values('PICKUP',20,'sound','DSITEMUP',255,128)
  into doom_audio_event_def values('DOOR_OPEN',25,'sound','DSDOROPN',240,180)
  into doom_audio_event_def values('MONSTER_WAKE',30,'sound','DSPOSIT1',220,80)
  into doom_audio_event_def values('MONSTER_PAIN',40,'sound','DSPOPAIN',220,128)
  into doom_audio_event_def values('MONSTER_DEATH',40,'sound','DSPODTH1',240,128)
  into doom_audio_event_def values('BARREL_EXPLODE',45,'sound','DSBAREXP',255,128)
  into doom_audio_event_def values('PLAYER_PAIN',50,'sound','DSPLPAIN',255,128)
select 1 from dual;

