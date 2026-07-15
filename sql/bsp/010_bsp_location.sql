whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

create or replace function doom_bsp_side(
  p_x number,
  p_y number,
  p_node_x number,
  p_node_y number,
  p_node_dx number,
  p_node_dy number
) return varchar2 sql_macro(scalar)
is
begin
  return q'~
    case
      when p_node_dx = 0 then
        case
          when p_x <= p_node_x then case when p_node_dy > 0 then 1 else 0 end
          else case when p_node_dy < 0 then 1 else 0 end
        end
      when p_node_dy = 0 then
        case
          when p_y <= p_node_y then case when p_node_dx < 0 then 1 else 0 end
          else case when p_node_dx > 0 then 1 else 0 end
        end
      else
        case
          when (p_x - p_node_x) * p_node_dy
             - (p_y - p_node_y) * p_node_dx > 0 then 0
          else 1
        end
    end
  ~';
end;
/

create or replace function doom_bsp_locate(
  p_x number,
  p_y number
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select
      located.ssector_id,
      facing_side.sector_id,
      located.depth,
      located.path_signature
    from (
      select
        max(case when traversal.child_is_ssector = 1 then traversal.child_id end) as ssector_id,
        max(case when traversal.child_is_ssector = 1 then traversal.depth end) as depth,
        listagg(
          to_char(traversal.node_id, 'FM9999999990', 'NLS_NUMERIC_CHARACTERS=''.,''')
          || ':' ||
          to_char(traversal.side, 'FM0', 'NLS_NUMERIC_CHARACTERS=''.,'''),
          '/'
        ) within group (order by traversal.depth) as path_signature
      from (
        select
          n.node_id,
          level as depth,
          doom_bsp_side(p_x, p_y, n.x, n.y, n.dx, n.dy) as side,
          case doom_bsp_side(p_x, p_y, n.x, n.y, n.dx, n.dy)
            when 0 then n.child0_is_ssector
            else n.child1_is_ssector
          end as child_is_ssector,
          case doom_bsp_side(p_x, p_y, n.x, n.y, n.dx, n.dy)
            when 0 then n.child0_id
            else n.child1_id
          end as child_id
        from doom_map_node n
        start with n.node_id = (select max(node_id) from doom_map_node)
        connect by nocycle
          prior case doom_bsp_side(p_x, p_y, n.x, n.y, n.dx, n.dy)
            when 0 then n.child0_is_ssector
            else n.child1_is_ssector
          end = 0
          and n.node_id = prior case doom_bsp_side(p_x, p_y, n.x, n.y, n.dx, n.dy)
            when 0 then n.child0_id
            else n.child1_id
          end
        order siblings by n.node_id
      ) traversal
    ) located
    join doom_map_ssector ssector
      on ssector.ssector_id = located.ssector_id
    join doom_map_seg first_seg
      on first_seg.seg_id = ssector.first_seg_id
    join doom_map_linedef linedef
      on linedef.linedef_id = first_seg.linedef_id
    join doom_map_sidedef facing_side
      on facing_side.sidedef_id = case first_seg.direction
        when 0 then linedef.right_sidedef_id
        else linedef.left_sidedef_id
      end
    order by located.depth
  ~';
end;
/

-- NODES ingestion decodes the WAD 0x8000 (32768) leaf bit into each
-- CHILD*_IS_SSECTOR flag and stores the masked 0x7fff child in CHILD*_ID.
