-- DoomDB Oracle capability probe.
-- Run only as the disposable DOOMDB_PROBE schema created by run.sh.
-- This file is also the reviewed P11 cloud probe; keep its cloud copy identical.

whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off
set feedback on
set heading on
set pagesize 100
set serveroutput on size unlimited

alter session set nls_numeric_characters = '.,';
alter session set nls_territory = 'AMERICA';
alter session set nls_language = 'AMERICAN';
alter session set time_zone = 'UTC';

prompt [SDO_GEOMETRY_INDEX]
create table probe_geometry (
  geometry_id number primary key,
  shape mdsys.sdo_geometry not null
);

insert into probe_geometry values (
  1,
  mdsys.sdo_geometry(2001, null, mdsys.sdo_point_type(10, 20, null), null, null)
);

insert into user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
values (
  'PROBE_GEOMETRY',
  'SHAPE',
  mdsys.sdo_dim_array(
    mdsys.sdo_dim_element('X', -100, 100, 0.005),
    mdsys.sdo_dim_element('Y', -100, 100, 0.005)
  ),
  null
);

create index probe_geometry_sidx on probe_geometry(shape)
  indextype is mdsys.spatial_index_v2;

select case count(*)
         when 1 then 'SDO_GEOMETRY_INDEX_OK'
         else to_char(1 / 0)
       end as result,
       count(*) as result_count
from probe_geometry
where sdo_filter(
        shape,
        mdsys.sdo_geometry(
          2003,
          null,
          null,
          mdsys.sdo_elem_info_array(1, 1003, 3),
          mdsys.sdo_ordinate_array(0, 0, 30, 30)
        )
      ) = 'TRUE'
  and sdo_geom.validate_geometry_with_context(shape, 0.005) = 'TRUE';

prompt [CONNECT_BY]
select case count(*)
         when 4 then 'CONNECT_BY_OK'
         else to_char(1 / 0)
       end as result,
       listagg(level, ',') within group (order by level) as result_value
from dual
connect by level <= 4;

prompt [MODEL]
select case listagg(position || ':' || model_value, ',')
              within group (order by position)
         when '1:1,2:2,3:4,4:8' then 'MODEL_OK'
         else to_char(1 / 0)
       end as result,
       listagg(position || ':' || model_value, ',')
         within group (order by position) as result_value
from (
  select position, model_value
  from (
    select level as position, cast(0 as number) as model_value
    from dual
    connect by level <= 4
  )
  model
    dimension by (position)
    measures (model_value)
    rules sequential order (
      model_value[1] = 1,
      model_value[for position from 2 to 4 increment 1] =
        model_value[cv(position) - 1] * 2
    )
);

prompt [MATCH_RECOGNIZE]
select case listagg(y0 || ':' || run_length || ':' || palette_index, ',')
              within group (order by y0)
         when '0:2:7,2:3:3' then 'MATCH_RECOGNIZE_OK'
         else to_char(1 / 0)
       end as result,
       listagg(y0 || ':' || run_length || ':' || palette_index, ',')
         within group (order by y0) as result_value
from (
  select y0, run_length, palette_index
  from (
    select 0 as y, 7 as palette_index from dual union all
    select 1 as y, 7 as palette_index from dual union all
    select 2 as y, 3 as palette_index from dual union all
    select 3 as y, 3 as palette_index from dual union all
    select 4 as y, 3 as palette_index from dual
  )
  match_recognize (
    order by y
    measures
      first(y) as y0,
      count(*) as run_length,
      first(palette_index) as palette_index
    one row per match
    pattern (run_start run_tail*)
    define
      run_tail as palette_index = prev(palette_index)
  )
);

prompt [JSON_RETURNING_CLOB]
declare
  payload clob;
begin
  select json_object(
           'probe' value 'json-clob',
           'values' value json_arrayagg(value order by value returning clob)
           returning clob
         )
  into payload
  from (
    select 2 as value from dual
    union all
    select 1 as value from dual
  );

  if dbms_lob.getlength(payload) = 0
     or dbms_lob.instr(payload, '"values":[1,2]') = 0 then
    raise_application_error(-20001, 'JSON RETURNING CLOB produced an unexpected payload');
  end if;
  dbms_output.put_line('JSON_RETURNING_CLOB_OK bytes=' || dbms_lob.getlength(payload));
end;
/

prompt [SQL_PROPERTY_GRAPH]
create table probe_vertex (
  vertex_id number primary key,
  vertex_name varchar2(30) not null
);

create table probe_edge (
  edge_id number primary key,
  source_id number not null references probe_vertex(vertex_id),
  target_id number not null references probe_vertex(vertex_id),
  edge_name varchar2(30) not null
);

insert all
  into probe_vertex values (1, 'start')
  into probe_vertex values (2, 'finish')
select 1 from dual;

insert into probe_edge values (1, 1, 2, 'reaches');

create property graph probe_property_graph
  vertex tables (
    probe_vertex
      key (vertex_id)
      label probe_vertex
      properties (vertex_id, vertex_name)
  )
  edge tables (
    probe_edge
      key (edge_id)
      source key (source_id) references probe_vertex(vertex_id)
      destination key (target_id) references probe_vertex(vertex_id)
      label probe_edge
      properties (edge_id, edge_name)
  );

select case count(*)
         when 1 then 'SQL_PROPERTY_GRAPH_OK'
         else to_char(1 / 0)
       end as result,
       min(source_id) || '->' || min(target_id) as result_value
from graph_table (
  probe_property_graph
  match (source is probe_vertex)-[edge is probe_edge]->(target is probe_vertex)
  columns (
    source.vertex_id as source_id,
    target.vertex_id as target_id
  )
)
where source_id = 1 and target_id = 2;

prompt [DBMS_CRYPTO]
declare
  digest raw(32);
begin
  digest := dbms_crypto.hash(
    utl_raw.cast_to_raw('doomdb-capability-probe'),
    dbms_crypto.hash_sh256
  );

  if utl_raw.length(digest) != 32 then
    raise_application_error(-20003, 'DBMS_CRYPTO SHA-256 returned an unexpected length');
  end if;
  dbms_output.put_line(
    'DBMS_CRYPTO_OK sha256=' || lower(rawtohex(digest))
  );
end;
/

prompt [UTL_COMPRESS]
declare
  source_blob blob;
  compressed_blob blob;
  restored_blob blob;
  source_raw raw(32767) := utl_raw.cast_to_raw(
    'doomdb capability probe doomdb capability probe doomdb capability probe'
  );
begin
  dbms_lob.createtemporary(source_blob, true);
  dbms_lob.writeappend(source_blob, utl_raw.length(source_raw), source_raw);
  compressed_blob := utl_compress.lz_compress(source_blob);
  restored_blob := utl_compress.lz_uncompress(compressed_blob);

  if dbms_lob.compare(source_blob, restored_blob) != 0 then
    raise_application_error(-20002, 'UTL_COMPRESS round trip mismatch');
  end if;
  dbms_output.put_line(
    'UTL_COMPRESS_OK source_bytes=' || dbms_lob.getlength(source_blob) ||
    ' compressed_bytes=' || dbms_lob.getlength(compressed_blob)
  );

  dbms_lob.freetemporary(restored_blob);
  dbms_lob.freetemporary(compressed_blob);
  dbms_lob.freetemporary(source_blob);
end;
/

prompt [ORDS_ENABLE_OBJECT]
create table probe_ords_object (
  probe_id number primary key,
  probe_value varchar2(30) not null
);

insert into probe_ords_object values (1, 'ords-enabled');
commit;

begin
  ords.enable_schema(
    p_enabled             => true,
    p_schema              => user,
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => lower(user),
    p_auto_rest_auth      => true
  );
  ords.enable_object(
    p_enabled        => true,
    p_schema         => user,
    p_object         => 'PROBE_ORDS_OBJECT',
    p_object_type    => 'TABLE',
    p_object_alias   => 'probe-ords-object',
    p_auto_rest_auth => true
  );
  dbms_output.put_line('ORDS_ENABLE_OBJECT_OK object=PROBE_ORDS_OBJECT enabled=true');
end;
/

begin
  ords.drop_rest_for_schema(p_schema => user);
end;
/

prompt ALL_ORACLE_CAPABILITY_PROBES_OK
exit success commit
