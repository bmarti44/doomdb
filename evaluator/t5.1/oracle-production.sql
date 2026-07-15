whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

declare
  k_token constant varchar2(32):='51515151515151515151515151515151';
  l_weapon varchar2(32); l_count number; l_bad number;
  procedure fail(m varchar2) is begin raise_application_error(-20951,m); end;
  procedure ok(v boolean,m varchar2) is begin if not v then fail(m);end if;end;
begin
  select count(*) into l_count from user_objects where object_name in ('DOOM_R2_PORTAL_HITS','DOOM_R2_SECTOR_INTERVALS') and object_type='FUNCTION' and status='VALID';ok(l_count=2,'valid reviewed macros');
  select min(weapon_id) into l_weapon from doom_weapon_def;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
    values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T51',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
    values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  select count(*) into l_count from table(doom_r2_portal_hits(k_token));ok(l_count>320,'complete ordered hit rows absent');
  select count(*) into l_bad from (select column_no,hit_ordinal,count(*) n from table(doom_r2_portal_hits(k_token)) group by column_no,hit_ordinal having count(*)<>1);ok(l_bad=0,'duplicate hit ordinal');
  select count(*) into l_bad from table(doom_r2_portal_hits(k_token)) where is_active not in (0,1) or is_closed not in (0,1) or is_transition not in (0,1) or is_termination not in (0,1);ok(l_bad=0,'invalid flags');
  select count(*) into l_bad from table(doom_r2_portal_hits(k_token)) where is_transition=1 and (from_sector_id is null or to_sector_id is null or opening_top<=opening_bottom);ok(l_bad=0,'invalid transition');
  select count(*) into l_bad from table(doom_r2_sector_intervals(k_token)) where t_start<0 or t_end<t_start or sector_id is null;ok(l_bad=0,'invalid intervals');
  select count(*) into l_bad from (select column_no,interval_ordinal,t_start,lag(t_end) over(partition by column_no order by interval_ordinal) prior_end from table(doom_r2_sector_intervals(k_token))) where interval_ordinal>0 and t_start<>prior_end;ok(l_bad=0,'noncontiguous intervals');
  rollback;dbms_output.put_line('PASS T5.1-ORACLE-PRODUCTION');
end;
/
