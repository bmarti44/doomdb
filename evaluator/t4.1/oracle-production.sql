whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

set constraints all deferred;

declare
  k_token constant varchar2(32):='41414141414141414141414141414141';
  l_weapon varchar2(32); l_count number; l_t number; l_u number; l_line number; l_seg number; l_side number;
  procedure fail(m varchar2) is begin raise_application_error(-20941,m); end;
  procedure eq(a number,e number,n varchar2) is begin if a is null or a!=e then fail(n||' expected '||e||' got '||nvl(to_char(a),'NULL'));end if;end;
  procedure near(a number,e number,t number,n varchar2) is begin if a is null or abs(a-e)>t then fail(n||' numeric mismatch');end if;end;
  procedure probe(c number,et number,eu number,el number,es number,ef number,n varchar2) is
  begin select hit_t,hit_u,linedef_id,seg_id,facing_side into l_t,l_u,l_line,l_seg,l_side from table(doom_r1_nearest(k_token)) where column_no=c;
    near(l_t,et,1e-6,n||' t');near(l_u,eu,1e-9,n||' u');eq(l_line,el,n||' line');eq(l_seg,es,n||' seg');eq(l_side,ef,n||' facing');end;
  procedure pose(px number,py number,pa number,expected_hits number,n varchar2) is
  begin update players set x=px,y=py,angle=pa where session_token=k_token and player_id=0;
    select count(*) into l_count from table(doom_r1_rays(k_token));eq(l_count,320,n||' rays');
    select count(*) into l_count from table(doom_r1_hits(k_token));eq(l_count,expected_hits,n||' hits');
    select count(*) into l_count from table(doom_r1_nearest(k_token));eq(l_count,320,n||' solids');
  end;
begin
  select min(weapon_id) into l_weapon from doom_weapon_def;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
    values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T41',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
    values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  select count(*) into l_count from user_objects where object_name in ('DOOM_R1_RAYS','DOOM_R1_HITS','DOOM_R1_NEAREST') and object_type='FUNCTION' and status='VALID';eq(l_count,3,'valid macro interface');
  pose(-416,256,0,12558,'spawn east');probe(0,160,.4921875,826,465,0,'east c0');probe(159,1480,.421875,892,698,0,'east c159');probe(160,1744,.886458333333333,961,1283,0,'east c160');probe(319,160,.5078125,827,456,0,'east c319');
  pose(-416,256,90,4141,'spawn north');probe(0,160.501567398119,.492163009404389,827,456,0,'north c0');probe(159,192,.01875,919,480,0,'north c159');probe(160,192,.9875,898,469,0,'north c160');probe(319,96.3009404388715,.003134796238245,902,509,0,'north c319');
  pose(128,256,180,4552,'central west');probe(0,256.802507836991,.987460815047022,544,562,0,'west c0');probe(159,800,.582589285714286,1049,517,0,'west c159');probe(160,800,.560267857142857,1049,517,0,'west c160');probe(319,256,.0125,549,1670,0,'west c319');
  rollback;dbms_output.put_line('PASS T4.1-ORACLE-PRODUCTION');
end;
/
