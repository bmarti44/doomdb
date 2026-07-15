whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
  l_count number;l_value number;
  procedure fail(m varchar2) is begin raise_application_error(-20963,m);end;
  procedure ok(v boolean,m varchar2) is begin if not v then fail(m);end if;end;
begin
  select count(*) into l_count from user_objects where object_name='DOOM_WORLD_MACHINES' and object_type='PACKAGE' and status='VALID';ok(l_count=1,'valid DOOM_WORLD_MACHINES package absent');
  select count(*) into l_count from user_procedures where object_name='DOOM_WORLD_MACHINES' and procedure_name='ADVANCE';ok(l_count=1,'ADVANCE procedure absent');
  select count(*) into l_count from doom_map_linedef where special in(1,2,11,23,26,62,88,117);ok(l_count>0,'required E1M1 line-special instances absent');
  select count(distinct special) into l_count from doom_map_linedef where special in(1,2,11,23,26,62,88,117);ok(l_count=8,'not every reviewed E1M1 line special present');
  select count(distinct special) into l_count from doom_map_sector where special in(1,7,9,12);ok(l_count=4,'not every reviewed E1M1 sector special present');
  select count(*) into l_count from doom_linedef_special_def where (special_id=1 and semantics='USE|REPEAT|DOOR_OPEN_WAIT_CLOSE') or (special_id=2 and semantics='WALK|ONCE|DOOR_OPEN_STAY') or (special_id=11 and semantics='USE|ONCE|EXIT') or (special_id=23 and semantics='USE|ONCE|FLOOR_LOWER_LOWEST') or (special_id=26 and semantics='USE|REPEAT|BLUE_KEY|DOOR_OPEN_WAIT_CLOSE') or (special_id=62 and semantics='USE|REPEAT|LIFT_LOWER_WAIT_RAISE') or (special_id=88 and semantics='WALK|REPEAT|LIFT_LOWER_WAIT_RAISE') or (special_id=117 and semantics='USE|REPEAT|BLAZING_DOOR_OPEN_WAIT_CLOSE');ok(l_count=8,'line semantics drift');
  select count(*) into l_count from doom_sector_special_def where (special_id=1 and semantics='LIGHT_RANDOM_BLINK') or (special_id=7 and semantics='DAMAGE_5|DAMAGE_EVERY_32_TICS') or (special_id=9 and semantics='SECRET_ONCE') or (special_id=12 and semantics='LIGHT_SYNC_SLOW_STROBE');ok(l_count=4,'sector semantics drift');
  select count(*) into l_count from doom_config where (config_key='WORLD_USE_RANGE' and number_value=64) or (config_key='WORLD_BUTTON_TICS' and number_value=35) or (config_key='WORLD_DOOR_SPEED' and number_value=2) or (config_key='WORLD_BLAZE_SPEED' and number_value=8) or (config_key='WORLD_DOOR_WAIT' and number_value=150) or (config_key='WORLD_LIFT_SPEED' and number_value=1) or (config_key='WORLD_LIFT_WAIT' and number_value=105) or (config_key='WORLD_DAMAGE_PERIOD' and number_value=32) or (config_key='WORLD_DAMAGE_AMOUNT' and number_value=5) or (config_key='WORLD_STROBE_BRIGHT' and number_value=5) or (config_key='WORLD_STROBE_DARK' and number_value=35);ok(l_count=11,'reviewed world constants absent');
  -- Real E1M1 geometry replay: select a production line for every reviewed
  -- special, derive front/back points independently, and let ADVANCE discover
  -- the activation. No linedef id or trigger decision is passed to production.
  declare
    k_weapon varchar2(32);k_seq number:=0;
    procedure replay(p_special number,p_key number default 1) is
      k_token varchar2(32);k_line number;k_x1 number;k_y1 number;k_x2 number;k_y2 number;k_dx number;k_dy number;k_len number;
      k_front_x number;k_front_y number;k_back_x number;k_back_y number;k_angle number;k_use number;k_before number;
    begin
      k_seq:=k_seq+1;
      select lower(substr(standard_hash('T63-'||p_special||'-'||k_seq,'MD5'),1,32)) into k_token from dual;
      select linedef_id,v1.x,v1.y,v2.x,v2.y into k_line,k_x1,k_y1,k_x2,k_y2 from doom_map_linedef l join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id where l.special=p_special fetch first 1 row only;
      k_dx:=k_x2-k_x1;k_dy:=k_y2-k_y1;k_len:=sqrt(k_dx*k_dx+k_dy*k_dy);
      k_front_x:=(k_x1+k_x2)/2+k_dy/k_len*8;k_front_y:=(k_y1+k_y2)/2-k_dx/k_len*8;
      k_back_x:=(k_x1+k_x2)/2-k_dy/k_len*8;k_back_y:=(k_y1+k_y2)/2+k_dx/k_len*8;
      k_use:=case when p_special in(1,11,23,26,62,117) then 1 else 0 end;
      k_angle:=mod(atan2((k_y1+k_y2)/2-k_front_y,(k_x1+k_x2)/2-k_front_x)*180/acos(-1)+360,360);
      insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at) values(k_token,'GAME',3,1,0,'ACTIVE',0,'NONE','OFF',null,'T63',0,systimestamp+interval '1' hour,systimestamp);
      insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip) values(k_token,0,case when k_use=1 then k_front_x else k_back_x end,case when k_use=1 then k_front_y else k_back_y end,0,0,0,0,k_angle,41,0,100,0,0,p_key,0,0,50,0,0,0,1,k_weapon,0,0,0,0,0,0,0,1,0);
      update game_sessions set current_player_id=0 where session_token=k_token;
      insert into sector_state(session_token,sector_id,floor_height,ceiling_height,light_level,secret_found,damage_clock) select k_token,sector_id,floor_height,ceiling_height,light_level,0,0 from doom_map_sector;
      insert into line_state(session_token,linedef_id,trigger_count,switch_on) select k_token,linedef_id,0,0 from doom_map_linedef;
      insert into tic_commands(session_token,command_seq,tic,command_ordinal,turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,automap_toggle,menu_action,cheat_code,command_sha) values(k_token,1,1,0,0,0,0,0,0,k_use,0,0,0,'NONE',null,rpad('0',64,'0'));
      doom_world_machines.advance(k_token,1,k_front_x,k_front_y);
      select trigger_count into k_before from line_state where session_token=k_token and linedef_id=k_line;
      if p_special=26 and p_key=0 then ok(k_before=0,'blue denial consumed special 26');else ok(k_before=1,'special '||p_special||' geometry replay did not trigger');end if;
      if p_special=11 then select count(*) into l_count from game_sessions where session_token=k_token and map_status='COMPLETED';ok(l_count=1,'exit replay did not complete map');end if;
      delete from game_sessions where session_token=k_token;
    end;
  begin
    select weapon_id into k_weapon from (select weapon_id from doom_weapon_def order by slot_number) where rownum=1;
    replay(1);replay(2);replay(11);replay(23);replay(26,0);replay(26,1);replay(62);replay(88);replay(117);
  end;
  rollback;
  dbms_output.put_line('PASS T6.3-ORACLE-PRODUCTION');
end;
/
