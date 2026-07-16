whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace function doom_perf_exact_visible(
  p_session in varchar2,p_x in number,p_y in number,p_source in number,
  p_target_x in number,p_target_y in number,p_target in number
) return number authid current_user is
  rejected_ number;blockers_ number;
begin
  select coalesce(max(rejected),1) into rejected_ from doom_sector_reject
    where source_sector_id=p_source and target_sector_id=p_target;
  if rejected_=1 then return 0;end if;
  select count(*) into blockers_
    from doom_block_cell bc
    join doom_block_line bl on bl.cell_id=bc.cell_id
    join doom_los_segment los on los.linedef_id=bl.linedef_id
    join doom_map_sector rs on rs.sector_id=los.right_sector_id
    left join sector_state rss on rss.session_token=p_session and rss.sector_id=rs.sector_id
    left join doom_map_sector ls on ls.sector_id=los.left_sector_id
    left join sector_state lss on lss.session_token=p_session and lss.sector_id=ls.sector_id
    where bc.world_min_x<=greatest(p_x,p_target_x)
      and bc.world_min_x+128>=least(p_x,p_target_x)
      and bc.world_min_y<=greatest(p_y,p_target_y)
      and bc.world_min_y+128>=least(p_y,p_target_y)
      and greatest(los.vx,los.vx+los.sx)>=least(p_x,p_target_x)
      and least(los.vx,los.vx+los.sx)<=greatest(p_x,p_target_x)
      and greatest(los.vy,los.vy+los.sy)>=least(p_y,p_target_y)
      and least(los.vy,los.vy+los.sy)<=greatest(p_y,p_target_y)
      and ((p_target_x-p_x)*los.sy-(p_target_y-p_y)*los.sx)<>0
      and ((los.vx-p_x)*los.sy-(los.vy-p_y)*los.sx) /
          ((p_target_x-p_x)*los.sy-(p_target_y-p_y)*los.sx)>0
      and ((los.vx-p_x)*los.sy-(los.vy-p_y)*los.sx) /
          ((p_target_x-p_x)*los.sy-(p_target_y-p_y)*los.sx)<1
      and ((los.vx-p_x)*(p_target_y-p_y)-(los.vy-p_y)*(p_target_x-p_x)) /
          ((p_target_x-p_x)*los.sy-(p_target_y-p_y)*los.sx) between 0 and 1
      and (los.left_sector_id is null
        or least(coalesce(rss.ceiling_height,rs.ceiling_height),
                 coalesce(lss.ceiling_height,ls.ceiling_height))
           <=greatest(coalesce(rss.floor_height,rs.floor_height),
                      coalesce(lss.floor_height,ls.floor_height)));
  return case when blockers_>0 then 0 else 1 end;
exception when others then return -1;
end;
/

declare
  session_ varchar2(32);payload_ blob;snapshot_ clob;result_ varchar2(4000);
  source_sector_ number;target_sector_ number;expected_ number;actual_ number;
  cases_ pls_integer:=0;open_cases_ pls_integer:=0;visible_cases_ pls_integer:=0;
  samples_ sys.odcinumberlist:=sys.odcinumberlist();started_ timestamp with time zone;
  elapsed_ interval day to second;ms_ number;p50_ number;p95_ number;max_ number;
  actors_ clob;player_x_ number;player_y_ number;player_sector_ number;
begin
  doom_api.new_game(3,session_,payload_);
  result_:=doom_sim_catalog_load;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  select json_arrayagg(json_array(sector_id,floor_height,ceiling_height
           returning varchar2) order by sector_id returning clob)
    into snapshot_ from sector_state where session_token=session_;
  result_:=doom_retained_los_load(snapshot_);
  if result_<>'OK|182' then raise_application_error(-20000,result_);end if;

  for ray_ in (
    with points as (
      select row_number() over(order by thing_id) ordinal,x,y,count(*) over() point_count
        from doom_map_thing
    ), sequence_ as (select level sequence_id from dual connect by level<=270)
    select a.x source_x,a.y source_y,b.x target_x,b.y target_y
      from sequence_ q join points a on a.ordinal=mod(q.sequence_id*17,a.point_count)+1
      join points b on b.ordinal=mod(q.sequence_id*43+11,b.point_count)+1
      order by q.sequence_id
  ) loop
    select sector_id into source_sector_
      from table(doom_bsp_locate(ray_.source_x,ray_.source_y)) where rownum=1;
    select sector_id into target_sector_
      from table(doom_bsp_locate(ray_.target_x,ray_.target_y)) where rownum=1;
    expected_:=doom_perf_exact_visible(session_,ray_.source_x,ray_.source_y,source_sector_,
      ray_.target_x,ray_.target_y,target_sector_);
    started_:=systimestamp;
    actual_:=doom_retained_los_visible(ray_.source_x,ray_.source_y,source_sector_,
      ray_.target_x,ray_.target_y,target_sector_);
    elapsed_:=systimestamp-started_;
    if actual_<>expected_ then
      raise_application_error(-20000,'LOS mismatch case='||cases_||' sectors='||
        source_sector_||','||target_sector_||' expected='||expected_||' actual='||actual_||
        ' error='||doom_retained_los_last_error);
    end if;
    cases_:=cases_+1;visible_cases_:=visible_cases_+case when actual_=1 then 1 else 0 end;
    if doom_sim_catalog_rejected(source_sector_,target_sector_)=0 then
      open_cases_:=open_cases_+1;
      ms_:=extract(day from elapsed_)*86400000+extract(hour from elapsed_)*3600000+
        extract(minute from elapsed_)*60000+extract(second from elapsed_)*1000;
      samples_.extend;samples_(samples_.count):=ms_;
    end if;
  end loop;
  if open_cases_=0 then raise_application_error(-20000,'LOS corpus has no open pairs');end if;
  select percentile_cont(.5) within group(order by column_value),
         percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(samples_);
  dbms_output.put_line('retained_los_parity='||cases_||'/'||cases_);
  dbms_output.put_line('retained_los_open_visible_cases='||open_cases_||'|'||visible_cases_);
  dbms_output.put_line('retained_los_open_call_ms='||
    round(p50_,3)||'|'||round(p95_,3)||'|'||round(max_,3));
  select p.x,p.y into player_x_,player_y_ from game_sessions g join players p
    on p.session_token=g.session_token and p.player_id=g.current_player_id
    where g.session_token=session_;
  select sector_id into player_sector_
    from table(doom_bsp_locate(player_x_,player_y_)) where rownum=1;
  select json_arrayagg(json_array(m.x,m.y,
           coalesce(m.sector_id,(select sector_id from table(doom_bsp_locate(m.x,m.y))
             where rownum=1)) returning varchar2)
           order by m.mobj_id returning clob)
    into actors_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  result_:=doom_retained_los_actor_benchmark(
    actors_,player_x_,player_y_,player_sector_,300);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  dbms_output.put_line('retained_los_actor_batch_benchmark='||result_);
  rollback;
end;
/
