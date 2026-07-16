whenever sqlerror exit failure rollback

create or replace function doom_resident_sim_load_player(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_tic in number,p_command_seq in number,
  p_x in binary_double,p_y in binary_double,p_z in binary_double,
  p_angle in binary_double
) return varchar2 as language java name
  'DoomResidentSimulationBench.loadPlayer(java.lang.String,java.lang.String,long,long,long,double,double,double,double) return java.lang.String';
/

create or replace function doom_resident_sim_load_exact_player(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_tic in number,p_command_seq in number,p_x in number,p_y in number,p_z in number,
  p_angle in binary_double
) return varchar2 as language java name
  'DoomResidentSimulationBench.loadExactPlayer(java.lang.String,java.lang.String,long,long,long,oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER,double) return java.lang.String';
/

create or replace function doom_resident_sim_step_turn(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_command_seq in number,p_turn in number
) return varchar2 as language java name
  'DoomResidentSimulationBench.stepTurn(java.lang.String,java.lang.String,long,long,int) return java.lang.String';
/

create or replace function doom_resident_sim_step_turn_batch(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_commands in raw
) return raw as language java name
  'DoomResidentSimulationBench.prepareTurnBatch(java.lang.String,java.lang.String,long,java.lang.String,byte[]) return byte[]';
/

create or replace function doom_resident_sim_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2
) return varchar2 as language java name
  'DoomResidentSimulationBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/

create or replace function doom_resident_sim_prepare_movement(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_commands in raw
) return raw as language java name
  'DoomResidentSimulationBench.prepareMovementBatch(java.lang.String,java.lang.String,long,java.lang.String,byte[]) return byte[]';
/

create or replace function doom_resident_sim_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2
) return varchar2 as language java name
  'DoomResidentSimulationBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/

create or replace function doom_resident_sim_benchmark_turn(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_iterations in number
) return varchar2 as language java name
  'DoomResidentSimulationBench.benchmarkTurn(java.lang.String,java.lang.String,long,int) return java.lang.String';
/

create or replace function doom_resident_sim_state(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomResidentSimulationBench.state(java.lang.String,java.lang.String,long) return java.lang.String';
/

create or replace function doom_resident_sim_pending_state(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomResidentSimulationBench.pendingState(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/

create or replace function doom_resident_sim_exact_state(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomResidentSimulationBench.exactState(java.lang.String,java.lang.String,long) return java.lang.String';
/

create or replace function doom_resident_sim_last_error return varchar2 as
language java name
  'DoomResidentSimulationBench.lastError() return java.lang.String';
/
