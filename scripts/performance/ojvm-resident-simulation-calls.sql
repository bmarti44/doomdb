whenever sqlerror exit failure rollback

create or replace function doom_resident_sim_load_player(
  p_session in varchar2,p_tic in number,p_command_seq in number,
  p_x in binary_double,p_y in binary_double,p_z in binary_double,
  p_angle in binary_double
) return varchar2 as language java name
  'DoomResidentSimulationBench.loadPlayer(java.lang.String,long,long,double,double,double,double) return java.lang.String';
/

create or replace function doom_resident_sim_step_turn(
  p_session in varchar2,p_command_seq in number,p_turn in number
) return varchar2 as language java name
  'DoomResidentSimulationBench.stepTurn(java.lang.String,long,int) return java.lang.String';
/

create or replace function doom_resident_sim_step_turn_batch(
  p_session in varchar2,p_commands in raw
) return raw as language java name
  'DoomResidentSimulationBench.stepTurnBatch(java.lang.String,byte[]) return byte[]';
/

create or replace function doom_resident_sim_benchmark_turn(
  p_session in varchar2,p_iterations in number
) return varchar2 as language java name
  'DoomResidentSimulationBench.benchmarkTurn(java.lang.String,int) return java.lang.String';
/

create or replace function doom_resident_sim_state(p_session in varchar2)
return varchar2 as language java name
  'DoomResidentSimulationBench.state(java.lang.String) return java.lang.String';
/

create or replace function doom_resident_sim_last_error return varchar2 as
language java name
  'DoomResidentSimulationBench.lastError() return java.lang.String';
/
