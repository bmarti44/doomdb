whenever sqlerror exit failure rollback

create or replace function doom_sim_catalog_build return varchar2 as
language java name 'DoomSimCatalogBench.buildCatalog() return java.lang.String';
/
create or replace function doom_sim_catalog_load return varchar2 as
language java name 'DoomSimCatalogBench.loadCatalog() return java.lang.String';
/
create or replace function doom_sim_catalog_summary return varchar2 as
language java name 'DoomSimCatalogBench.summary() return java.lang.String';
/
create or replace function doom_sim_catalog_locate(p_x in binary_double,p_y in binary_double)
return number as language java name
  'DoomSimCatalogBench.locateSector(double,double) return int';
/
create or replace function doom_sim_catalog_movement_x(
  p_angle_index in number,p_forward in number,p_strafe in number,p_run in number)
return number as language java name
  'DoomSimCatalogBench.movementX(int,int,int,int) return oracle.sql.NUMBER';
/
create or replace function doom_sim_catalog_movement_y(
  p_angle_index in number,p_forward in number,p_strafe in number,p_run in number)
return number as language java name
  'DoomSimCatalogBench.movementY(int,int,int,int) return oracle.sql.NUMBER';
/
create or replace function doom_sim_catalog_last_error return varchar2 as
language java name 'DoomSimCatalogBench.lastError() return java.lang.String';
/
