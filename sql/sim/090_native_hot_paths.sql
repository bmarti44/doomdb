whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

alter package doom_tic_tx compile body plsql_code_type=native reuse settings;
alter package doom_world_machines compile body plsql_code_type=native reuse settings;
alter package doom_combat compile body plsql_code_type=native reuse settings;
alter package doom_monsters compile body plsql_code_type=native reuse settings;
alter package doom_audio compile body plsql_code_type=native reuse settings;
alter function doom_sweep_contact compile plsql_code_type=native reuse settings;
alter function doom_player_move_payload compile plsql_code_type=native reuse settings;
