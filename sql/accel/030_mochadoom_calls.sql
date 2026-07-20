create or replace function doom_mocha_probe return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.probeSafe() return java.lang.String';
/

create or replace function doom_mocha_iwad_probe return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.iwadProbeSafe() return java.lang.String';
/

create or replace function doom_mocha_initialize return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.initializeSafe() return java.lang.String';
/

create or replace function doom_mocha_step(
  p_forward_move in number,
  p_side_move in number,
  p_angle_turn in number,
  p_buttons in number
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.stepSafe(int,int,int,int) return java.lang.String';
/

create or replace function doom_mocha_frame(p_output in blob) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.frameSafe(java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_step_frame(
  p_forward_move in number,
  p_side_move in number,
  p_angle_turn in number,
  p_buttons in number,
  p_output in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.stepFrameSafe(int,int,int,int,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_step_controls_frame(
  p_turn in number,
  p_forward in number,
  p_strafe in number,
  p_run in number,
  p_fire in number,
  p_use in number,
  p_weapon in number,
  p_pause in number,
  p_automap in number,
  p_menu in number,
  p_output in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.stepControlsFrameSafe(int,int,int,int,int,int,int,int,int,int,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_step_controls_payload(
  p_turn in number,
  p_forward in number,
  p_strafe in number,
  p_run in number,
  p_fire in number,
  p_use in number,
  p_weapon in number,
  p_pause in number,
  p_automap in number,
  p_menu in number,
  p_cheat in number,
  p_previous_state_sha in varchar2,
  p_output in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.stepControlsPayloadSafe(int,int,int,int,int,int,int,int,int,int,int,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_current_payload(
  p_previous_state_sha in varchar2,
  p_output in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.currentPayloadSafe(java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_save(p_output in blob) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.saveSafe(java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_load(
  p_input in blob,
  p_expected_sha in varchar2,
  p_expected_tic in number
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.loadSafe(java.sql.Blob,java.lang.String,long) return java.lang.String';
/

create or replace function doom_mocha_reconstruct(
  p_skill in number,
  p_episode in number,
  p_map in number,
  p_command_stream in blob,
  p_expected_frame_sha in varchar2
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.reconstructSafe(int,int,int,java.sql.Blob,java.lang.String) return java.lang.String';
/

create or replace function doom_mocha_new_game(
  p_skill in number,
  p_episode in number,
  p_map in number
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.newGameSafe(int,int,int) return java.lang.String';
/

create or replace function doom_mocha_dispose return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.disposeSafe() return java.lang.String';
/

create or replace function doom_mocha_benchmark(
  p_samples in number,
  p_warmups in number,
  p_forward_move in number,
  p_side_move in number,
  p_angle_turn in number,
  p_fire_every in number
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.benchmarkSafe(int,int,int,int,int,int) return java.lang.String';
/

-- Internal P13 feasibility surfaces. They are deliberately absent from
-- DOOM_API, so the disposable probe and benchmark cannot become public
-- AutoREST contracts before the match schema and capability fences exist.
create or replace function doom_mocha_multiplayer_probe return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.multiplayerProbeSafe() return java.lang.String';
/

create or replace function doom_mocha_multiplayer_benchmark(
  p_active_players in number,
  p_samples in number,
  p_warmups in number,
  p_output in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.multiplayerBenchmarkSafe(int,int,int,java.sql.Blob) return java.lang.String';
/

-- Production P13 retained-match entry points. The four caller-owned BLOB
-- locators are filled only for active player slots; inactive slots stay empty.
create or replace function doom_mocha_multiplayer_new_game(
  p_active_players in number,
  p_deathmatch in number,
  p_skill in number,
  p_episode in number,
  p_map in number,
  p_output0 in blob,
  p_output1 in blob,
  p_output2 in blob,
  p_output3 in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.multiplayerNewGamePayloadsSafe(int,int,int,int,int,java.sql.Blob,java.sql.Blob,java.sql.Blob,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_multiplayer_step(
  p_active_players in number,
  p_membership_bitmap in number,
  p_command_vector_hex in varchar2,
  p_previous_state_sha in varchar2,
  p_output0 in blob,
  p_output1 in blob,
  p_output2 in blob,
  p_output3 in blob
) return varchar2
as language java
name 'doomdb.mocha.DoomDbMochaAdapter.multiplayerStepPayloadsSafe(int,int,java.lang.String,java.lang.String,java.sql.Blob,java.sql.Blob,java.sql.Blob,java.sql.Blob) return java.lang.String';
/

create or replace function doom_mocha_multiplayer_reconstruct(
  p_active_players in number,p_deathmatch in number,p_skill in number,
  p_episode in number,p_map in number,p_command_stream in blob,
  p_initial_state_sha in varchar2,p_expected_state_sha in varchar2,
  p_output0 in blob,p_output1 in blob,p_output2 in blob,p_output3 in blob
) return varchar2 as language java
name 'doomdb.mocha.DoomDbMochaAdapter.multiplayerReconstructPayloadsSafe(int,int,int,int,int,java.sql.Blob,java.lang.String,java.lang.String,java.sql.Blob,java.sql.Blob,java.sql.Blob,java.sql.Blob) return java.lang.String';
/

-- Migration decoder for database-side gates: selected Mocha frames are raw
-- DMF3, while the preserved SQL renderer and older ledgers remain gzip.
create or replace function doom_mocha_payload_plain(p_payload in blob)
return blob authid definer is
  l_magic varchar2(4);l_plain blob;
begin
  if p_payload is null then raise_application_error(-20721,'payload required');end if;
  l_magic:=utl_raw.cast_to_varchar2(dbms_lob.substr(p_payload,4,1));
  if l_magic in('DMF3','DMF4') then return p_payload;end if;
  if rawtohex(dbms_lob.substr(p_payload,2,1))='1F8B' then
    l_plain:=utl_compress.lz_uncompress(p_payload);
    l_magic:=utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,4,1));
    if l_magic in('DMF3','DMF4') then return l_plain;end if;
  end if;
  raise_application_error(-20721,'unknown Mocha payload codec');
end;
/
