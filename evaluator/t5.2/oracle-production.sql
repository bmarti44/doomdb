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
 k constant varchar2(32):='52525252525252525252525252525252'; w varchar2(32); n number; bad number; h1 varchar2(64);h2 varchar2(64);checks number:=0;
 procedure fail(m varchar2) is begin raise_application_error(-20952,m);end;procedure eq(a number,e number,m varchar2) is begin checks:=checks+1;if a is null or a<>e then fail(m);end if;end;
 function frame_hash return varchar2 is b blob;r raw(4);begin dbms_lob.createtemporary(b,true);for p in(select palette_index from table(doom_r2_pixels(k)) order by column_no,row_no)loop r:=utl_raw.substr(utl_raw.cast_from_binary_integer(p.palette_index,utl_raw.big_endian),4,1);dbms_lob.writeappend(b,1,r);end loop;eq(dbms_lob.getlength(b),64000,'hash bytes');return lower(rawtohex(dbms_crypto.hash(b,dbms_crypto.hash_sh256)));end;
begin
 select count(*) into n from user_objects where object_name='DOOM_R2_PIXELS' and object_type='FUNCTION' and status='VALID';eq(n,1,'valid macro');select min(weapon_id)into w from doom_weapon_def;
 insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)values(k,'GAME',3,17,0,'ACTIVE',0,'NONE','OFF',null,'T52',0,systimestamp+interval '1' hour,systimestamp);
 insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)values(k,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,w,0,0,0,0,0,0,0,1);update game_sessions set current_player_id=0 where session_token=k;
 select count(*),count(distinct to_char(column_no,'FM000')||':'||to_char(row_no,'FM000')),sum(case when column_no not between 0 and 319 or row_no not between 0 and 199 or palette_index not between 0 and 255 or palette_index<>trunc(palette_index) or layer_ordinal not in(0,1,3,4,10,11,12) then 1 else 0 end)into n,bad,checks from table(doom_r2_pixels(k));if n<>64000 or bad<>64000 or checks<>0 then fail('dense frame');end if;checks:=3;
 select count(*)into bad from(select column_no,row_no from table(doom_r2_pixels(k))group by column_no,row_no having count(*)<>1);eq(bad,0,'duplicates');select count(*)into bad from((select c,r from(select level-1 c from dual connect by level<=320)cross join(select level-1 r from dual connect by level<=200))minus select column_no,row_no from table(doom_r2_pixels(k)));eq(bad,0,'gaps');
 select count(*)into bad from table(doom_r2_pixels(k))where layer_ordinal in(0,1,4) and sector_interval_ordinal is null;eq(bad,0,'plane interval ownership');h1:=frame_hash;h2:=frame_hash;if h1<>h2 then fail('rerun hash');end if;checks:=checks+1;
 rollback;dbms_output.put_line('PASS T5.2-ORACLE-PRODUCTION ('||checks||' live checks; SHA-256 '||h1||')');
end;
/
