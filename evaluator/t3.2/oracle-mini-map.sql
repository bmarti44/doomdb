whenever sqlerror exit failure rollback
set define off verify off feedback off heading off pagesize 0 serveroutput on
alter session set nls_numeric_characters='.,' nls_territory='AMERICA' nls_language='AMERICAN' time_zone='UTC';

declare
  l_user varchar2(128) := sys_context('USERENV', 'CURRENT_USER');
begin
  if l_user not like 'DOOMDB_EVAL%' then
    raise_application_error(-20832, 'T32_MINIMAP_REQUIRES_DOOMDB_EVAL_SCHEMA');
  end if;
end;
/

begin
  execute immediate 'drop table doom_eval_t32_line purge';
exception when others then
  if sqlcode != -942 then raise; end if;
end;
/

delete from user_sdo_geom_metadata
 where table_name = 'DOOM_EVAL_T32_LINE' and column_name = 'GEOM';

create table doom_eval_t32_line (
  line_id number(10) primary key,
  geom mdsys.sdo_geometry not null
);

insert into user_sdo_geom_metadata(table_name,column_name,diminfo,srid)
values ('DOOM_EVAL_T32_LINE','GEOM',
  mdsys.sdo_dim_array(
    mdsys.sdo_dim_element('X',-1000,101000,0.005),
    mdsys.sdo_dim_element('Y',-76000,1000,0.005)), null);

insert into doom_eval_t32_line values (1,
  mdsys.sdo_geometry(2002,null,null,
    mdsys.sdo_elem_info_array(1,2,1),
    mdsys.sdo_ordinate_array(0,0,10,10)));
insert into doom_eval_t32_line values (2,
  mdsys.sdo_geometry(2002,null,null,
    mdsys.sdo_elem_info_array(1,2,1),
    mdsys.sdo_ordinate_array(100000,-75000,100010,-74990)));
commit;

create index doom_eval_t32_sidx on doom_eval_t32_line(geom)
  indextype is mdsys.spatial_index_v2;

declare
  l_filter number;
  l_exact number;
  l_true_a number;
  l_true_b number;
  l_translated_filter number;
  l_translated_exact number;
  procedure assert_eq(p_actual number, p_expected number, p_label varchar2) is
  begin
    if p_actual is null or p_actual != p_expected then
      raise_application_error(-20833, p_label || ': expected ' || p_expected || ', got ' || nvl(to_char(p_actual),'NULL'));
    end if;
  end;
begin
  select count(*) into l_filter
    from doom_eval_t32_line l
   where l.line_id = 1
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(0,9,1,10))) = 'TRUE';
  select count(*) into l_exact
    from doom_eval_t32_line l
   where l.line_id = 1
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(0,9,1,10))) = 'TRUE'
     and sdo_relate(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(0,9,1,10)),
       'mask=ANYINTERACT') = 'TRUE';
  select count(*) into l_true_a
    from doom_eval_t32_line l
   where l.line_id = 1
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(4,4,6,6))) = 'TRUE'
     and sdo_relate(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(4,4,6,6)),
       'mask=ANYINTERACT') = 'TRUE';
  select count(*) into l_true_b
    from doom_eval_t32_line l
   where l.line_id = 1
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(9,9,11,11))) = 'TRUE'
     and sdo_relate(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(9,9,11,11)),
       'mask=ANYINTERACT') = 'TRUE';
  select count(*) into l_translated_filter
    from doom_eval_t32_line l
   where l.line_id = 2
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(100000,-74991,100001,-74990))) = 'TRUE';
  select count(*) into l_translated_exact
    from doom_eval_t32_line l
   where l.line_id = 2
     and sdo_filter(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(100004,-74996,100006,-74994))) = 'TRUE'
     and sdo_relate(l.geom, mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(100004,-74996,100006,-74994)),
       'mask=ANYINTERACT') = 'TRUE';

  assert_eq(l_filter,1,'MBR false-positive candidate');
  assert_eq(l_exact,0,'exact false-positive removal');
  assert_eq(l_true_a,1,'first exact positive');
  assert_eq(l_true_b,1,'boundary exact positive');
  assert_eq(l_translated_filter,1,'translated MBR candidate');
  assert_eq(l_translated_exact,1,'translated exact positive');
  dbms_output.put_line('PASS T3.2-ORACLE-MINI-MAP (6/6 assertions)');
end;
/

drop table doom_eval_t32_line purge;
delete from user_sdo_geom_metadata
 where table_name = 'DOOM_EVAL_T32_LINE' and column_name = 'GEOM';
commit;
