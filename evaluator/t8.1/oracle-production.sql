whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';
declare
 c number;
 procedure fail(m varchar2) is begin raise_application_error(-20881,m);end;
 procedure ok(b boolean,m varchar2) is begin if not b then fail(m);end if;end;
begin
 select count(*) into c from user_objects where object_name='DOOM_API' and object_type='PACKAGE' and status='VALID';ok(c=1,'valid DOOM_API package absent');
 select count(*) into c from user_procedures where object_name='DOOM_API' and procedure_name in('NEW_GAME','STEP','START_REPLAY','STEP_REPLAY');ok(c=4,'required public replay procedures absent or overloaded');
 select count(*) into c from user_tables where table_name in('GAME_SESSIONS','PLAYERS','MOBJS','SECTOR_STATE','LINE_STATE','ACTIVE_MOVERS','TIC_COMMANDS','GAME_EVENTS','AUDIO_EVENTS','STEP_RESPONSES','STATE_HISTORY');ok(c=11,'authoritative completion/history tables absent');
 select count(*) into c from user_tab_columns where table_name='GAME_SESSIONS' and column_name in('CURRENT_TIC','MAP_STATUS','RNG_CURSOR');ok(c=3,'session completion state incomplete');
 select count(*) into c from user_tab_columns where table_name='PLAYERS' and column_name in('KILL_COUNT','ITEM_COUNT','SECRET_COUNT','BLUE_KEY','YELLOW_KEY','RED_KEY');ok(c=6,'player completion counters and color-key flags incomplete');
 select count(*) into c from players
  where case when blue_key=1 or yellow_key=1 or red_key=1 then 1 else 0 end <>
        case when nvl(blue_key,0)+nvl(yellow_key,0)+nvl(red_key,0)>0 then 1 else 0 end;
 ok(c=0,'derived any-color-key condition inconsistent');
 select count(*) into c from doom_map_linedef where special in(1,26,62,88,117);ok(c>=5,'required route line specials absent from E1M1');
 select count(*) into c from doom_map_sector where special=9;ok(c>=1,'required E1M1 secret sector absent');
 select count(*) into c from user_source where name='DOOM_API' and type='PACKAGE BODY' and regexp_like(upper(text),'EVALUATOR|ROUTE-CANDIDATE|SCREENSHOTHASH|T81-');ok(c=0,'DOOM_API reads evaluator answers');
 dbms_output.put_line('PASS T8.1-ORACLE-PREREQUISITES (public replay API, authoritative history/counters, E1M1 route specials)');
end;
/
