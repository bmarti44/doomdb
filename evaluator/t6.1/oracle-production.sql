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
 k constant varchar2(32):='61616161616161616161616161616161'; p blob; p2 blob; n number; checks number:=0; before_counts varchar2(200); got number;
 c1 constant clob:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":1,"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
 c2 constant clob:='{"v":1,"commands":[{"seq":2,"turn":-1,"forward":0,"strafe":1,"run":1,"fire":0,"use":0,"weapon":0,"pause":1,"automap":1,"menu":"OPTIONS","cheat":"GOD"},{"seq":3,"turn":0,"forward":0,"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
 procedure fail(m varchar2) is begin raise_application_error(-20961,m);end;procedure eq(a number,e number,m varchar2) is begin checks:=checks+1;if a is null or a<>e then fail(m||' got '||a);end if;end;
 procedure expect_error(c clob,code number) is x blob;begin begin doom_tic_tx.apply_batch(k,c,x);fail('expected '||code);exception when others then if sqlcode<>code then raise;end if;end;checks:=checks+1;end;
 function counts return varchar2 is a number;b number;c number;d number;begin select count(*)into a from tic_commands where session_token=k;select count(*)into b from game_events where session_token=k;select count(*)into c from step_responses where session_token=k;select count(*)into d from state_history where session_token=k;return a||':'||b||':'||c||':'||d;end;
begin
 select count(*)into n from user_objects where object_name='DOOM_TIC_TX' and object_type='PACKAGE BODY' and status='VALID';eq(n,1,'valid package body');
 insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)values(k,'GAME',3,100,17,'ACTIVE',0,'NONE','OFF',null,'T61-A',0,systimestamp+interval '1' hour,systimestamp);
 insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)values(k,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,'PISTOL',0,0,0,0,0,0,0,1);update game_sessions set current_player_id=0 where session_token=k;
 doom_tic_tx.apply_batch(k,c1,p);select current_tic into n from game_sessions where session_token=k;eq(n,101,'single tic');select last_command_seq into n from game_sessions where session_token=k;eq(n,1,'single seq');eq(dbms_lob.getlength(p),236,'canonical payload bytes');
 select count(*)into n from tic_commands where session_token=k;eq(n,1,'one command');select count(*)into n from step_responses where session_token=k;eq(n,1,'one cache');select count(*)into n from state_history where session_token=k;eq(n,1,'one batch snapshot');
 before_counts:=counts;doom_tic_tx.apply_batch(k,c1,p2);if dbms_lob.compare(p,p2)<>0 then fail('retry bytes');end if;checks:=checks+1;if counts<>before_counts then fail('retry mutation');end if;checks:=checks+1;
 expect_error(replace(c1,'"forward":1','"forward":0'),-20862);if counts<>before_counts then fail('conflict mutation');end if;checks:=checks+1;
 expect_error(replace(c1,'"seq":1','"seq":3'),-20864);expect_error('{}',-20861);
 doom_tic_tx.apply_batch(k,c2,p);select current_tic,last_command_seq into n,got from game_sessions where session_token=k;eq(n,103,'two logical tics');eq(got,3,'frontier three');select count(*)into n from game_events where session_token=k and tic=102 and event_ordinal between 0 and 3;eq(n,4,'dense control events');select count(*)into n from game_events where session_token=k and tic=102 and ((event_ordinal=0 and event_type='CONTROL_PAUSE')or(event_ordinal=1 and event_type='CONTROL_MENU')or(event_ordinal=2 and event_type='CONTROL_AUTOMAP')or(event_ordinal=3 and event_type='CONTROL_CHEAT'));eq(n,4,'event order');
 select count(*)into n from step_responses where session_token=k and state_sha='a9a979368fc35e0d39899d787d1cfdd7538e15e06931b835a429fc8d119dcf74';eq(n,1,'independent state hash');
 select count(*)into n from state_history where session_token=k;eq(n,2,'one snapshot per accepted batch');
 rollback;dbms_output.put_line('PASS T6.1-ORACLE-PRODUCTION ('||checks||' live checks)');
end;
/
