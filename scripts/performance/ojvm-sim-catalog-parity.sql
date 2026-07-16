whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  result_ varchar2(4000);failures_ pls_integer:=0;cases_ pls_integer:=0;
  sql_sector number;java_sector number;sql_x number;sql_y number;java_x number;java_y number;
  matrix_failures_ number;rng_expected_ number;spread_cases_ number:=0;
  function same_number(p_left number,p_right number) return boolean is same_ number;begin
    select case when dump(p_left,16)=dump(p_right,16) then 1 else 0 end into same_ from dual;
    return same_=1;
  end;
begin
  result_:=doom_sim_catalog_build;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  result_:=doom_sim_catalog_load;
  if not regexp_like(result_,'^OK\|681\|682\|1175\|182\|1152\|[0-9a-f]{64}$') then
    raise_application_error(-20000,'catalog summary '||result_);
  end if;

  -- Deterministic interior/boundary grid across the map bounds.
  for index_ in 0..269 loop
    declare
      x_ number:=-2048+mod(index_*104729,7168);
      y_ number:=-2048+mod(index_*130363,7168);
    begin
      select sector_id into sql_sector from table(doom_bsp_locate(x_,y_)) where rownum=1;
      java_sector:=doom_sim_catalog_locate(to_binary_double(x_),to_binary_double(y_));
      cases_:=cases_+1;
      if java_sector<>sql_sector then
        failures_:=failures_+1;
        if failures_<=10 then dbms_output.put_line('locate mismatch x='||x_||' y='||y_||
          ' java='||java_sector||' sql='||sql_sector);end if;
      end if;
    end;
  end loop;
  if failures_<>0 then raise_application_error(-20000,'catalog locate failures='||failures_);end if;

  for angle_index_ in 0..63 loop
    for forward_ in -1..1 loop
      for strafe_ in -1..1 loop
        for run_ in 0..1 loop
          declare angle_ number:=angle_index_*5.625;begin
            sql_x:=(forward_*cos(angle_*acos(-1)/180)+strafe_*sin(angle_*acos(-1)/180))*8*(run_+1);
            sql_y:=(forward_*sin(angle_*acos(-1)/180)-strafe_*cos(angle_*acos(-1)/180))*8*(run_+1);
            java_x:=doom_sim_catalog_movement_x(angle_index_,forward_,strafe_,run_);
            java_y:=doom_sim_catalog_movement_y(angle_index_,forward_,strafe_,run_);
            if not same_number(java_x,sql_x) or not same_number(java_y,sql_y) then
              raise_application_error(-20000,'catalog movement mismatch');
            end if;
          end;
        end loop;
      end loop;
    end loop;
  end loop;
  select count(*) into matrix_failures_ from doom_map_sector s
    cross join doom_map_sector t
    left join doom_sector_reject r on r.source_sector_id=s.sector_id
      and r.target_sector_id=t.sector_id
    left join doom_sector_sound_reach a on a.source_sector_id=s.sector_id
      and a.target_sector_id=t.sector_id
    where doom_sim_catalog_rejected(s.sector_id,t.sector_id)<>coalesce(r.rejected,1)
       or doom_sim_catalog_sound_reach(s.sector_id,t.sector_id)<>
          case when a.source_sector_id is null then 0 else 1 end;
  if matrix_failures_<>0 then
    raise_application_error(-20000,'catalog sector matrix failures='||matrix_failures_);
  end if;
  for index_ in 0..255 loop
    select rng_value into rng_expected_ from doom_rng_value where rng_index=index_;
    if doom_sim_catalog_rng(index_)<>rng_expected_ then
      raise_application_error(-20000,'catalog RNG mismatch index='||index_);
    end if;
  end loop;
  for difference_ in -255..255 loop
    if not same_number(doom_sim_catalog_hitscan_spread(difference_),
          difference_*2*acos(-1)/4096) or
       not same_number(doom_sim_catalog_hitscan_sin(difference_),
          sin(difference_*2*acos(-1)/4096)) or
       doom_sim_catalog_hitscan_spread_text(difference_)<>
          to_char(difference_*2*acos(-1)/4096,'TM9',
            'NLS_NUMERIC_CHARACTERS=''.,''') then
      raise_application_error(-20000,'hitscan spread mismatch difference='||difference_);
    end if;
    spread_cases_:=spread_cases_+1;
  end loop;
  for state_ in (
    select s.state_index,s.tics,coalesce(n.state_index,-1) next_index,
      case s.action_name when 'CHASE' then 1 when 'MELEE' then 2
        when 'HITSCAN' then 3 when 'PROJECTILE' then 4 else 0 end action_code
      from (select d.*,row_number() over(order by state_id)-1 state_index
        from doom_state_def d) s
      left join (select state_id,row_number() over(order by state_id)-1 state_index
        from doom_state_def) n on n.state_id=s.next_state_id order by s.state_index
  ) loop
    if doom_sim_catalog_state_tics(state_.state_index)<>state_.tics or
       doom_sim_catalog_state_next(state_.state_index)<>state_.next_index or
       doom_sim_catalog_state_action(state_.state_index)<>state_.action_code then
      raise_application_error(-20000,'catalog state mismatch index='||state_.state_index);
    end if;
  end loop;
  dbms_output.put_line('sim_catalog_summary='||doom_sim_catalog_summary);
  dbms_output.put_line('sim_catalog_bsp_locate_parity='||cases_||'/'||cases_);
  dbms_output.put_line('sim_catalog_movement_parity=1152/1152');
  dbms_output.put_line('sim_catalog_reject_sound_parity=33124/33124');
  dbms_output.put_line('sim_catalog_rng_parity=256/256');
  dbms_output.put_line('sim_catalog_hitscan_spread_parity='||spread_cases_||'/511');
  dbms_output.put_line('sim_catalog_state_graph_parity=151/151');
end;
/
