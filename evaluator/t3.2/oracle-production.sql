whenever sqlerror exit failure rollback
set define off verify off feedback off heading off pagesize 0 serveroutput on
alter session set nls_numeric_characters='.,' nls_territory='AMERICA' nls_language='AMERICAN' time_zone='UTC';

declare
  l_n number;
  l_min_x number; l_max_x number; l_min_y number; l_max_y number;
  l_far number; l_radius number;
  l_lb_x number; l_ub_x number; l_tol_x number;
  l_lb_y number; l_ub_y number; l_tol_y number;
  l_srid number;
  l_diminfo mdsys.sdo_dim_array;
  l_geom mdsys.sdo_geometry;
  l_shape_bad number := 0;
  l_endpoint_bad number := 0;
  l_status varchar2(30); l_dom_status varchar2(30); l_op_status varchar2(30); l_type varchar2(30);
  procedure assert_eq(p_actual number, p_expected number, p_label varchar2) is
  begin
    if p_actual is null or p_actual != p_expected then
      raise_application_error(-20834,p_label || ': expected ' || p_expected || ', got ' || nvl(to_char(p_actual),'NULL'));
    end if;
  end;
  procedure assert_text(p_actual varchar2, p_expected varchar2, p_label varchar2) is
  begin
    if p_actual is null or p_actual != p_expected then
      raise_application_error(-20835,p_label || ': expected ' || p_expected || ', got ' || nvl(p_actual,'NULL'));
    end if;
  end;
begin
  select count(*) into l_n from doom_vertex; assert_eq(l_n,1196,'vertex count');
  select count(*) into l_n from doom_linedef; assert_eq(l_n,1175,'linedef count');
  select min(x),max(x),min(y),max(y) into l_min_x,l_max_x,l_min_y,l_max_y from doom_vertex;
  assert_eq(l_min_x,-704,'min x'); assert_eq(l_max_x,3248,'max x');
  assert_eq(l_min_y,-1064,'min y'); assert_eq(l_max_y,2336,'max y');
  select number_value into l_far from doom_config where config_key='FAR_DISTANCE';
  select number_value into l_radius from doom_config where config_key='PLAYER_RADIUS';
  assert_eq(l_far,8192,'far distance'); assert_eq(l_radius,16,'player radius');

  select m.diminfo,m.srid
    into l_diminfo,l_srid
    from user_sdo_geom_metadata m
   where m.table_name='DOOM_LINEDEF' and m.column_name='GEOM';
  l_lb_x := l_diminfo(1).sdo_lb;
  l_ub_x := l_diminfo(1).sdo_ub;
  l_tol_x := l_diminfo(1).sdo_tolerance;
  l_lb_y := l_diminfo(2).sdo_lb;
  l_ub_y := l_diminfo(2).sdo_ub;
  l_tol_y := l_diminfo(2).sdo_tolerance;
  assert_eq(l_lb_x,l_min_x-l_far-l_radius,'derived x lower');
  assert_eq(l_ub_x,l_max_x+l_far+l_radius,'derived x upper');
  assert_eq(l_lb_y,l_min_y-l_far-l_radius,'derived y lower');
  assert_eq(l_ub_y,l_max_y+l_far+l_radius,'derived y upper');
  assert_eq(l_tol_x,0.005,'x tolerance'); assert_eq(l_tol_y,0.005,'y tolerance');
  if l_srid is not null then raise_application_error(-20836,'metadata SRID must be null'); end if;

  for r in (
    select l.geom,a.x as start_x,a.y as start_y,b.x as end_x,b.y as end_y
      from doom_linedef l
      join doom_vertex a on a.vertex_id=l.start_vertex_id
      join doom_vertex b on b.vertex_id=l.end_vertex_id
     order by l.linedef_id
  ) loop
    l_geom := r.geom;
    if l_geom is null then
      l_shape_bad := l_shape_bad + 1;
      l_endpoint_bad := l_endpoint_bad + 1;
    elsif l_geom.sdo_gtype != 2002 or l_geom.sdo_srid is not null
       or l_geom.sdo_point is not null then
      l_shape_bad := l_shape_bad + 1;
    else
      begin
        if l_geom.sdo_elem_info.count != 3
           or l_geom.sdo_elem_info(1) != 1
           or l_geom.sdo_elem_info(2) != 2
           or l_geom.sdo_elem_info(3) != 1
           or l_geom.sdo_ordinates.count != 4 then
          l_shape_bad := l_shape_bad + 1;
        end if;
        if l_geom.sdo_ordinates.count != 4
           or l_geom.sdo_ordinates(1) != r.start_x
           or l_geom.sdo_ordinates(2) != r.start_y
           or l_geom.sdo_ordinates(3) != r.end_x
           or l_geom.sdo_ordinates(4) != r.end_y then
          l_endpoint_bad := l_endpoint_bad + 1;
        end if;
      exception
        when collection_is_null or subscript_beyond_count then
          l_shape_bad := l_shape_bad + 1;
          l_endpoint_bad := l_endpoint_bad + 1;
      end;
    end if;
  end loop;
  assert_eq(l_shape_bad,0,'canonical geometry shape');
  assert_eq(l_endpoint_bad,0,'directed geometry endpoints');

  select count(*) into l_n from doom_linedef
   where nvl(mdsys.sdo_geom.validate_geometry_with_context(geom,0.005),'NULL') != 'TRUE';
  assert_eq(l_n,0,'geometry validity');

  select count(*) into l_n
    from doom_linedef l
    join doom_vertex a on a.vertex_id=l.start_vertex_id
    join doom_vertex b on b.vertex_id=l.end_vertex_id
   where l.length != round(sqrt(power(b.x-a.x,2)+power(b.y-a.y,2)),12)
      or l.direction_x != round((b.x-a.x)/sqrt(power(b.x-a.x,2)+power(b.y-a.y,2)),12)
      or l.direction_y != round((b.y-a.y)/sqrt(power(b.x-a.x,2)+power(b.y-a.y,2)),12);
  assert_eq(l_n,0,'stable metrics');

  select status,domidx_status,domidx_opstatus,index_type
    into l_status,l_dom_status,l_op_status,l_type
    from user_indexes where index_name='DOOM_LINEDEF_SIDX';
  assert_text(l_status,'VALID','index status');
  assert_text(l_dom_status,'VALID','domain index status');
  assert_text(l_op_status,'VALID','domain operator status');
  assert_text(l_type,'DOMAIN','index type');

  select count(*) into l_n
    from doom_linedef l
   where l.linedef_id=0
     and sdo_filter(l.geom,mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(2623.5,607,2625,609)))='TRUE';
  assert_eq(l_n,1,'pinned MBR false-positive candidate');
  select count(*) into l_n
    from doom_linedef l
   where l.linedef_id=0
     and sdo_filter(l.geom,mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(2623.5,607,2625,609)))='TRUE'
     and sdo_relate(l.geom,mdsys.sdo_geometry(2003,null,null,
       mdsys.sdo_elem_info_array(1,1003,3),mdsys.sdo_ordinate_array(2623.5,607,2625,609)),
       'mask=ANYINTERACT')='TRUE';
  assert_eq(l_n,0,'pinned exact false-positive removal');
  dbms_output.put_line('PASS T3.2-ORACLE-PRODUCTION');
end;
/
