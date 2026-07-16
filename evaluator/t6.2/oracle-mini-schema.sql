whenever sqlerror exit sql.sqlcode rollback
set define off serveroutput on size unlimited
declare l_user varchar2(128):=sys_context('USERENV','CURRENT_USER');begin if l_user not like 'DOOMDB_EVAL%' then raise_application_error(-20862,'T62_MINIMAP_REQUIRES_EVAL_SCHEMA');end if;end;
/
create table doom_config(config_key varchar2(64) primary key,number_value number,text_value varchar2(4000));
insert into doom_config values('PLAYER_RADIUS',16,null);
create table game_sessions(session_token varchar2(32) primary key,current_player_id number);
create table players(session_token varchar2(32),player_id number,x number,y number,z number,view_height number,primary key(session_token,player_id));
create table doom_map_sector(sector_id number primary key,floor_height number,ceiling_height number);
create table sector_state(session_token varchar2(32),sector_id number,floor_height number,ceiling_height number,primary key(session_token,sector_id));
create table doom_map_vertex(vertex_id number primary key,x number,y number);
create table doom_map_sidedef(sidedef_id number primary key,sector_id number);
create table doom_map_linedef(linedef_id number primary key,start_vertex_id number,end_vertex_id number,flags number,right_sidedef_id number,left_sidedef_id number);
create table doom_linedef(linedef_id number primary key,start_vertex_id number,end_vertex_id number,flags number,right_sidedef_id number,left_sidedef_id number,geom mdsys.sdo_geometry,length number,direction_x number,direction_y number);
create table doom_collision_segment(linedef_id number primary key,flags number,left_sector_id number,right_sector_id number,start_vertex_id number,end_vertex_id number,x1 number,y1 number,x2 number,y2 number,min_x number,max_x number,min_y number,max_y number,segment_length number,direction_x number,direction_y number);
create table doom_block_cell(cell_id number primary key,block_x number,block_y number,world_min_x number,world_min_y number,list_word_offset number);
create table doom_block_line(cell_id number,line_ordinal number,linedef_id number,primary key(cell_id,line_ordinal));
create table eval_region(boundary_x number,low_sector number,high_sector number);
insert into user_sdo_geom_metadata(table_name,column_name,diminfo,srid) values('DOOM_LINEDEF','GEOM',mdsys.sdo_dim_array(mdsys.sdo_dim_element('X',-5000,5000,.005),mdsys.sdo_dim_element('Y',-5000,5000,.005)),null);
create index doom_linedef_sidx on doom_linedef(geom) indextype is mdsys.spatial_index_v2;
create or replace function doom_bsp_locate(p_x number,p_y number)return varchar2 sql_macro(table)is begin return q'~select 0 ssector_id,case when r.boundary_x is null then (select min(sector_id) from doom_map_sector) when p_x<r.boundary_x then r.low_sector else r.high_sector end sector_id,1 depth,'EVAL' path_signature from (select max(boundary_x) boundary_x,max(low_sector) low_sector,max(high_sector) high_sector from eval_region) r~';end;
/
commit;
