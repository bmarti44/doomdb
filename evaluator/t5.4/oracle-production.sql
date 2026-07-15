whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

declare
  k_token constant varchar2(32):='54545454545454545454545454545454';
  l_weapon varchar2(32);l_count number;l_bad number;l_world_sha varchar2(64);l_again varchar2(64);
  procedure fail(m varchar2) is begin raise_application_error(-20954,m);end;
  procedure ok(v boolean,m varchar2) is begin if not v then fail(m);end if;end;
  procedure assert_canvas(label varchar2) is
  begin
    select count(*),sum(case when column_no between 0 and 319 and row_no between 0 and 199 and palette_index between 0 and 255 then 0 else 1 end)
      into l_count,l_bad from table(doom_r2_presentation(k_token));ok(l_count=64000,label||' row count');ok(l_bad=0,label||' ranges');
    select count(*) into l_bad from (select column_no,row_no,count(*) n from table(doom_r2_presentation(k_token)) group by column_no,row_no having count(*)<>1);ok(l_bad=0,label||' duplicate/gap');
  end;
begin
  select count(*) into l_count from user_objects where object_name='DOOM_R2_PRESENTATION' and object_type='FUNCTION' and status='VALID';ok(l_count=1,'valid reviewed macro');
  select weapon_id into l_weapon from (select weapon_id from doom_weapon_def order by slot_number) where rownum=1;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
    values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T54',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
    values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  assert_canvas('game');
  select count(*) into l_count from table(doom_r2_presentation(k_token)) where source_kind in ('WEAPON','HUD_PATCH','TEXT');ok(l_count>0,'weapon/HUD/text sources absent');
  update game_sessions set paused=1 where session_token=k_token;assert_canvas('paused');select count(*) into l_count from table(doom_r2_presentation(k_token)) where source_kind='PAUSE';ok(l_count>0,'pause patch absent');
  update game_sessions set paused=0,game_mode='MENU',menu_state='2' where session_token=k_token;assert_canvas('menu');select count(*) into l_count from table(doom_r2_presentation(k_token)) where source_kind in ('MENU_PATCH','TEXT');ok(l_count>0,'menu layers absent');
  update game_sessions set game_mode='AUTOMAP',automap_state='ON' where session_token=k_token;assert_canvas('automap');
  select count(*) into l_count from table(doom_r2_presentation(k_token)) p where p.source_kind='AUTOMAP_LINE';ok(l_count>0,'automap lines absent');
  select count(*) into l_bad from table(doom_r2_presentation(k_token)) p where p.source_kind='AUTOMAP_LINE' and not exists(select 1 from doom_linedef l where to_char(l.linedef_id)=p.source_id);ok(l_bad=0,'automap source is not relational linedef');
  update game_sessions set game_mode='INTERMISSION',automap_state='OFF',map_status='COMPLETE' where session_token=k_token;assert_canvas('intermission');select count(*) into l_count from table(doom_r2_presentation(k_token)) where source_kind in ('INTERMISSION_PATCH','TEXT');ok(l_count>0,'intermission layers absent');
  select count(*) into l_bad from table(doom_r2_presentation(k_token)) where source_kind='TEXT' and (column_no not between 0 and 319 or row_no not between 0 and 199);ok(l_bad=0,'text out of bounds');
  rollback;dbms_output.put_line('PASS T5.4-ORACLE-PRODUCTION');
end;
/
