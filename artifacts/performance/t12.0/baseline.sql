whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited
set timing on pages 100 lines 220
set constraints all deferred

declare
  k_token constant varchar2(32) := '12001200120012001200120012001200';
  l_weapon varchar2(32);
begin
  delete from game_sessions where session_token=k_token;
  select min(weapon_id) into l_weapon from doom_weapon_def;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,17,0,'ACTIVE',0,'NONE','OFF',null,'T120',0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,
    1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
end;
/

column stage format a20
select 'WORLD' stage,count(*) rows_,sum(palette_index) palette_sum,
  sum(column_no*1000+row_no) coord_sum
from doom_r2_pixel_rows
where session_token='12001200120012001200120012001200';

select 'MASKED_SELECTED' stage,count(*) rows_,sum(palette_index) palette_sum,
  sum(column_no*1000+row_no) coord_sum
from doom_r2_masked_candidate_rows
where session_token='12001200120012001200120012001200'
  and is_selected=1;

select 'PRESENTATION' stage,count(*) rows_,sum(palette_index) palette_sum,
  sum(column_no*1000+row_no) coord_sum
from table(doom_r2_presentation('12001200120012001200120012001200'));

rollback;
