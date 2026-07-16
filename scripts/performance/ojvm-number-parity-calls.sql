whenever sqlerror exit failure rollback

create or replace function doom_number_delta_x(
  p_angle in number,p_forward in number,p_strafe in number,p_run in number)
return number as language java name
  'DoomOracleNumberParityBench.movementDeltaX(oracle.sql.NUMBER,int,int,int) return oracle.sql.NUMBER';
/

create or replace function doom_number_delta_y(
  p_angle in number,p_forward in number,p_strafe in number,p_run in number)
return number as language java name
  'DoomOracleNumberParityBench.movementDeltaY(oracle.sql.NUMBER,int,int,int) return oracle.sql.NUMBER';
/

create or replace function doom_number_quadratic_entry(
  p_px in number,p_py in number,p_ex in number,p_ey in number,
  p_dx in number,p_dy in number,p_radius in number)
return number as language java name
  'DoomOracleNumberParityBench.quadraticEntry(oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER,oracle.sql.NUMBER) return oracle.sql.NUMBER';
/

create or replace function doom_number_benchmark(p_iterations in number)
return varchar2 as language java name
  'DoomOracleNumberParityBench.benchmarkMovement(int) return java.lang.String';
/

create or replace function doom_number_lookup_benchmark(p_iterations in number)
return varchar2 as language java name
  'DoomOracleNumberParityBench.benchmarkLookup(int) return java.lang.String';
/

create or replace function doom_number_quadratic_benchmark(p_iterations in number)
return varchar2 as language java name
  'DoomOracleNumberParityBench.benchmarkQuadratic(int) return java.lang.String';
/

create or replace function doom_number_last_error return varchar2 as
language java name
  'DoomOracleNumberParityBench.lastError() return java.lang.String';
/
