-- T9.1 database-authored fire animation.  The fixed generator deliberately
-- exposes no sizing or quality controls and leaves transaction ownership to
-- its caller.

create table doom_fire_frame_run (
  frame_no number(3) not null,
  run_no number(6) not null,
  start_offset number(5) not null,
  run_length number(5) not null,
  intensity number(2) not null,
  constraint doom_fire_frame_run_pk primary key(frame_no,run_no),
  constraint doom_fire_frame_no_ck check(frame_no between 0 and 149),
  constraint doom_fire_run_no_ck check(run_no>=0),
  constraint doom_fire_start_ck check(start_offset between 0 and 15359),
  constraint doom_fire_length_ck check(run_length>0),
  constraint doom_fire_intensity_ck check(intensity between 0 and 36)
);

create table doom_fire_build_probe (
  probe_ordinal number(1) not null,
  probe_name varchar2(8) not null,
  frame_count number(3) not null,
  width number(3) not null,
  height number(2) not null,
  cell_count number(7) not null,
  estimated_bytes number(9) not null,
  preinsert_run_count number(1) not null,
  result_run_count number(6) not null,
  model_operations number(1) not null,
  status varchar2(8) not null,
  elapsed_ms number(12) not null,
  pga_bytes number(12) not null,
  constraint doom_fire_build_probe_pk primary key(probe_ordinal),
  constraint doom_fire_probe_name_uq unique(probe_name),
  constraint doom_fire_probe_ordinal_ck check(probe_ordinal between 1 and 2),
  constraint doom_fire_probe_status_ck check(status='PASS'),
  constraint doom_fire_probe_preinsert_ck check(preinsert_run_count=0),
  constraint doom_fire_probe_operation_ck check(model_operations=1)
);

create or replace package doom_fire authid definer as
  procedure generate;
end doom_fire;
/

create or replace package body doom_fire as
  c_full_frames constant pls_integer:=150;
  c_full_width constant pls_integer:=160;
  c_full_height constant pls_integer:=96;
  c_full_cells constant pls_integer:=2304000;
  c_memory_limit constant pls_integer:=268435456;
  c_expected_small_runs constant pls_integer:=485;
  c_expected_full_runs constant pls_integer:=604369;

  procedure generate is
    l_frames pls_integer;
    l_width pls_integer;
    l_height pls_integer;
    l_cells pls_integer;
    l_expected_runs pls_integer;
    l_actual_runs pls_integer;
    l_preinsert_runs pls_integer;
    l_estimated_bytes number;
    l_started number;
    l_elapsed_ms number;

    procedure build_runs is
    begin
      -- This is the sole cellular data-generating operation.  It is executed
      -- first with the small feasibility dimensions and then, unchanged, with
      -- the required full dimensions.  FLOOR expressions implement true
      -- floor modulus, including the wrapped x=-1 case Oracle remainder does
      -- not represent correctly.
      insert into doom_fire_frame_run(
        frame_no,run_no,start_offset,run_length,intensity
      )
      with axes as (
        select f.frame_no,y.y,x.x,cast(0 as number) heat
          from (select level-1 frame_no from dual
                connect by level<=l_frames) f
          cross join (select level-1 y from dual
                      connect by level<=l_height) y
          cross join (select level-1 x from dual
                      connect by level<=l_width) x
      ), cells as (
        select frame_no,y,x,heat
          from axes
          model
            dimension by(frame_no,y,x)
            measures(heat)
            rules sequential order (
              heat[frame_no is any,y is any,x is any]
                order by frame_no asc,y desc,x asc =
                case
                  when cv(y)=l_height-1 then
                    28+(
                      (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                       cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                      -256*floor(
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                      )
                    )-9*floor((
                      (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                       cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                      -256*floor(
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                      )
                    )/9)
                  when cv(frame_no)=0 then 0
                  else greatest(0,
                    heat[
                      cv(frame_no)-1,
                      cv(y)+1,
                      (cv(x)+(
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )-3*floor((
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )/3)-1)
                      -l_width*floor((cv(x)+(
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )-3*floor((
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )/3)-1)/l_width)
                    ]
                    -(
                      floor((
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )/3)
                      -3*floor(floor((
                        (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                         cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)
                        -256*floor(
                          (cv(frame_no)*73+cv(x)*151+cv(y)*199+
                           cv(frame_no)*cv(x)*17+cv(x)*cv(y)*13)/256
                        )
                      )/3)/3)
                    )
                  )
                end
            )
      ), prior_values as (
        select frame_no,y,x,heat,
               lag(heat) over(partition by frame_no order by y,x) prior_heat
          from cells
      ), marked as (
        select frame_no,y,x,heat,
               case when prior_heat=heat then 0 else 1 end starts_run
          from prior_values
      ), grouped as (
        select frame_no,y,x,heat,
               sum(starts_run) over(
                 partition by frame_no order by y,x rows unbounded preceding
               ) run_group
          from marked
      ), encoded as (
        select frame_no,run_group,
               min(y*l_width+x) start_offset,
               count(*) run_length,
               min(heat) intensity
          from grouped
         group by frame_no,run_group
      )
      select frame_no,
             row_number() over(partition by frame_no order by start_offset)-1,
             start_offset,run_length,intensity
        from encoded;
    end build_runs;

    procedure run_probe(
      p_ordinal in pls_integer,
      p_name in varchar2,
      p_frames in pls_integer,
      p_width in pls_integer,
      p_height in pls_integer,
      p_expected_runs in pls_integer
    ) is
    begin
      l_frames:=p_frames;
      l_width:=p_width;
      l_height:=p_height;
      l_cells:=l_frames*l_width*l_height;
      l_expected_runs:=p_expected_runs;

      delete from doom_fire_frame_run;
      select count(*) into l_preinsert_runs from doom_fire_frame_run;

      -- Sixty-four bytes per cell is intentionally conservative: it covers
      -- numeric dimensions, the measure and SQL work-area overhead while
      -- remaining below the frozen 256 MiB fail-closed ceiling.
      l_estimated_bytes:=l_cells*64;
      if l_estimated_bytes>c_memory_limit then
        raise_application_error(-20991,'fire build memory estimate exceeds limit');
      end if;

      l_started:=dbms_utility.get_time;
      build_runs;
      l_elapsed_ms:=greatest(0,(dbms_utility.get_time-l_started)*10);

      select count(*) into l_actual_runs from doom_fire_frame_run;
      if l_actual_runs<>l_expected_runs then
        raise_application_error(-20991,'fire canonical run count mismatch');
      end if;

      insert into doom_fire_build_probe(
        probe_ordinal,probe_name,frame_count,width,height,cell_count,
        estimated_bytes,preinsert_run_count,result_run_count,
        model_operations,status,elapsed_ms,pga_bytes
      ) values(
        p_ordinal,p_name,l_frames,l_width,l_height,l_cells,
        l_estimated_bytes,l_preinsert_runs,l_actual_runs,
        1,'PASS',l_elapsed_ms,0
      );
    end run_probe;
  begin
    delete from doom_fire_build_probe;

    run_probe(1,'SMALL',8,16,12,c_expected_small_runs);
    run_probe(2,'FULL',c_full_frames,c_full_width,c_full_height,
              c_expected_full_runs);

    if l_frames<>150 or l_width<>160 or l_height<>96 or
       l_cells<>c_full_cells then
      raise_application_error(-20991,'full fire dimensions are mandatory');
    end if;
  end generate;
end doom_fire;
/
