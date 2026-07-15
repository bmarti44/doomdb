whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
  n number;
  procedure ok(v boolean,m varchar2) is begin if not v then raise_application_error(-21010,m);end if;end;
  procedure exact_arg(p_proc varchar2,p_pos number,p_name varchar2,p_mode varchar2,p_type varchar2) is begin
    select count(*) into n from user_arguments where package_name='DOOM_API' and object_name=p_proc and position=p_pos and argument_name=p_name and in_out=p_mode and data_type=p_type;ok(n=1,p_proc||' argument '||p_pos||' drift');
  end;
begin
  select count(*) into n from user_objects where object_name='DOOM_API' and object_type in('PACKAGE','PACKAGE BODY') and status='VALID';ok(n=2,'valid package/spec absent');
  select count(*) into n from user_procedures where object_name='DOOM_API' and procedure_name is not null;ok(n=7,'public member count drift');
  select count(*) into n from (select procedure_name,count(*) c from user_procedures where object_name='DOOM_API' and procedure_name is not null group by procedure_name having count(*)<>1);ok(n=0,'overloaded/duplicate public member');
  select count(*) into n from user_procedures where object_name='DOOM_API' and procedure_name in('NEW_GAME','STEP','SAVE_GAME','LOAD_GAME','START_REPLAY','STEP_REPLAY','GET_ASSET');ok(n=7,'public names drift');
  exact_arg('NEW_GAME',1,'P_SKILL','IN','NUMBER');exact_arg('NEW_GAME',2,'P_SESSION','OUT','VARCHAR2');exact_arg('NEW_GAME',3,'P_PAYLOAD','OUT','BLOB');
  exact_arg('STEP',1,'P_SESSION','IN','VARCHAR2');exact_arg('STEP',2,'P_COMMANDS','IN','CLOB');exact_arg('STEP',3,'P_PAYLOAD','OUT','BLOB');
  exact_arg('SAVE_GAME',1,'P_SESSION','IN','VARCHAR2');exact_arg('SAVE_GAME',2,'P_SLOT','IN','NUMBER');exact_arg('SAVE_GAME',3,'P_STATE_SHA','OUT','VARCHAR2');
  exact_arg('LOAD_GAME',1,'P_SESSION','IN','VARCHAR2');exact_arg('LOAD_GAME',2,'P_SLOT','IN','NUMBER');exact_arg('LOAD_GAME',3,'P_PAYLOAD','OUT','BLOB');
  exact_arg('START_REPLAY',1,'P_SESSION','IN','VARCHAR2');exact_arg('START_REPLAY',2,'P_FROM_TIC','IN','NUMBER');exact_arg('START_REPLAY',3,'P_TO_TIC','IN','NUMBER');exact_arg('START_REPLAY',4,'P_REPLAY_ID','OUT','VARCHAR2');
  exact_arg('STEP_REPLAY',1,'P_REPLAY_ID','IN','VARCHAR2');exact_arg('STEP_REPLAY',2,'P_PAYLOAD','OUT','BLOB');
  exact_arg('GET_ASSET',1,'P_ASSET_NAME','IN','VARCHAR2');exact_arg('GET_ASSET',2,'P_PAYLOAD','OUT','BLOB');exact_arg('GET_ASSET',3,'P_MEDIA_TYPE','OUT','VARCHAR2');
  select count(*) into n from user_views where view_name='PUBLIC_HEALTH';ok(n=1,'PUBLIC_HEALTH absent');
  select count(*) into n from user_updatable_columns where table_name='PUBLIC_HEALTH' and (updatable='YES' or insertable='YES' or deletable='YES');ok(n=0,'PUBLIC_HEALTH is updatable');
  select count(*) into n from user_ords_enabled_objects;ok(n=2,'ORDS enabled-object count must be exactly two');
  select count(*) into n from user_ords_enabled_objects where parsing_object in('DOOM_API','PUBLIC_HEALTH');ok(n=2,'exact enabled objects absent');
  select count(*) into n from user_ords_enabled_objects where parsing_object not in('DOOM_API','PUBLIC_HEALTH');ok(n=0,'extra ORDS object exposed');
  select count(*) into n from user_tab_privs_made where table_name in('GAME_SESSIONS','PLAYERS','MOBJS','SECTOR_STATE','LINE_STATE','ACTIVE_MOVERS','ACTIVE_SWITCHES','TIC_COMMANDS','GAME_EVENTS','AUDIO_EVENTS','STEP_RESPONSES','STATE_HISTORY','SAVE_SLOTS');ok(n=0,'base state object grants exist');
  dbms_output.put_line('PASS T10.1-ORACLE-METADATA (exact package, exposure, non-updatability, least grants)');
end;
/
