whenever sqlerror exit sql.sqlcode rollback
set define off

create or replace function doom_ords_java_affinity_next return varchar2 as
language java name 'DoomOrdsAffinityProbe.next() return java.lang.String';
/

create or replace package doom_ords_affinity_probe authid definer as
  procedure next(
    p_java_counter out varchar2,
    p_plsql_counter out number,
    p_sid out number,
    p_audsid out number
  );
end doom_ords_affinity_probe;
/

create or replace function doom_ords_affinity_read return varchar2 is
  l_java varchar2(128);
  l_plsql number;
  l_sid number;
  l_audsid number;
begin
  doom_ords_affinity_probe.next(l_java,l_plsql,l_sid,l_audsid);
  return json_object(
    'java' value l_java,
    'plsql' value l_plsql,
    'sid' value l_sid,
    'audsid' value l_audsid
    returning varchar2);
end doom_ords_affinity_read;
/

create or replace package body doom_ords_affinity_probe as
  g_counter number := 0;

  procedure next(
    p_java_counter out varchar2,
    p_plsql_counter out number,
    p_sid out number,
    p_audsid out number
  ) is
  begin
    g_counter := g_counter + 1;
    p_java_counter := doom_ords_java_affinity_next;
    p_plsql_counter := g_counter;
    p_sid := to_number(sys_context('USERENV','SID'));
    p_audsid := to_number(sys_context('USERENV','SESSIONID'));
  exception when others then
    p_java_counter := 'ERROR:PLSQL:' || to_char(sqlcode);
    p_plsql_counter := g_counter;
    p_sid := to_number(sys_context('USERENV','SID'));
    p_audsid := to_number(sys_context('USERENV','SESSIONID'));
  end;
end doom_ords_affinity_probe;
/

begin
  ords.enable_object(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_object=>'DOOM_ORDS_AFFINITY_PROBE',
    p_object_type=>'PACKAGE',
    p_object_alias=>'doom_ords_affinity_probe',
    p_auto_rest_auth=>false);
  commit;
end;
/

begin
  ords.enable_object(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_object=>'DOOM_ORDS_AFFINITY_READ',
    p_object_type=>'FUNCTION',
    p_object_alias=>'doom_ords_affinity_read',
    p_auto_rest_auth=>false);
  commit;
end;
/
