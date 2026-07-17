whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Stateful retained-USE gate: transaction rollback, restart reconstruction,
-- lift carry/blocking, button reset, and door open/wait/close timelines.
-- Speeds and waits are shortened before each worker load; transition order and
-- durable effects are unchanged, making this bounded enough for CI.
declare
  type token_tab is table of varchar2(32) index by pls_integer;
  sessions_ token_tab;session_count_ pls_integer:=0;
  session_ varchar2(32);payload_ blob;commands_ clob;
  old_enabled_ number;old_parity_ number;old_failpoint_ number;old_split_use_ number;
  old_door_speed_ number;old_lift_speed_ number;old_door_wait_ number;old_lift_wait_ number;
  old_button_tics_ number;
  line_ number;target_ number;target_x_ number;target_y_ number;mobj_ number;
  origin_ number;bottom_ number;ceiling_ number;height_ number;direction_ number;timer_ number;
  count_ number;failed_ boolean;tic_ number;triggers_ number;generation_before_ number;generation_after_ number;
  world_pack_us_ number;world_apply_us_ number;prepare_us_ number;world_split_ number;world_active_ number;world_enabled_ number;

  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;

  procedure remember_(p_session varchar2) is
  begin session_count_:=session_count_+1;sessions_(session_count_):=p_session;end;

  procedure fixture_(
    p_special number,p_require_empty_target boolean,
    p_line out number,p_x out number,p_y out number,p_angle out number,
    p_sector out number,p_target out number,p_target_x out number,p_target_y out number
  ) is
    length_ number;mid_x_ number;mid_y_ number;occupants_ number;
  begin
    p_line:=null;
    for candidate_ in (
      select ml.linedef_id,ml.tag,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
             ls.sector_id left_sector
        from doom_map_linedef ml join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
        join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
        join doom_map_sidedef ls on ls.sidedef_id=ml.left_sidedef_id
        join doom_linedef_special_def d on d.special_id=ml.special
       where ml.special=p_special and instr(d.semantics,'USE|')=1
       order by case when ml.tag<>0 and exists(select 1 from doom_map_sector ms
                    where ms.sector_id=ls.sector_id and ms.tag=ml.tag) then 0 else 1 end,
                ml.linedef_id
    ) loop
      length_:=sqrt(power(candidate_.x2-candidate_.x1,2)+power(candidate_.y2-candidate_.y1,2));
      if length_=0 then continue;end if;
      mid_x_:=(candidate_.x1+candidate_.x2)/2;mid_y_:=(candidate_.y1+candidate_.y2)/2;
      p_x:=mid_x_+(candidate_.y2-candidate_.y1)*8/length_;
      p_y:=mid_y_-(candidate_.x2-candidate_.x1)*8/length_;
      p_target_x:=mid_x_-(candidate_.y2-candidate_.y1)*8/length_;
      p_target_y:=mid_y_+(candidate_.x2-candidate_.x1)*8/length_;
      p_angle:=mod(round(atan2(mid_y_-p_y,mid_x_-p_x)*180/acos(-1)/5.625)*5.625+360,360);
      begin
        select sector_id into p_sector from table(doom_bsp_locate(p_x,p_y)) where rownum=1;
        if candidate_.tag<>0 then
          -- Prefer a tagged line whose opposite sector is itself one target;
          -- this gives a deterministic point for the carry/block fixtures.
          select count(*) into occupants_ from doom_map_sector
            where sector_id=candidate_.left_sector and tag=candidate_.tag;
          if occupants_>0 then p_target:=candidate_.left_sector;
          else select min(sector_id) into p_target from doom_map_sector where tag=candidate_.tag;end if;
        else p_target:=candidate_.left_sector;end if;
        declare located_ number;begin
          select sector_id into located_ from table(doom_bsp_locate(p_target_x,p_target_y)) where rownum=1;
          if located_<>p_target then continue;end if;
        end;
        if p_require_empty_target then
          select count(*) into occupants_ from doom_map_thing t
            where exists(select 1 from table(doom_bsp_locate(t.x,t.y)) b where b.sector_id=p_target);
          if occupants_>0 then continue;end if;
        end if;
        p_line:=candidate_.linedef_id;exit;
      exception when no_data_found then null;end;
    end loop;
    assert_(p_line is not null,'no lifecycle fixture special '||p_special);
  end;

  procedure create_session_(
    p_special number,p_empty boolean,
    p_line out number,p_target out number,p_target_x out number,p_target_y out number
  ) is
    x_ number;y_ number;angle_ number;sector_ number;
  begin
    fixture_(p_special,p_empty,p_line,x_,y_,angle_,sector_,p_target,p_target_x,p_target_y);
    doom_api.new_game(3,session_,payload_);remember_(session_);
    update players set x=x_,y=y_,angle=angle_,
      z=(select floor_height from sector_state where session_token=session_ and sector_id=sector_)
      where session_token=session_ and player_id=(select current_player_id from game_sessions
        where session_token=session_);
    commit;
  end;

  procedure assert_integrity_(p_session varchar2,p_tic number,p_seq number) is
    lineage_ varchar2(64);command_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
    head_command_ varchar2(64);result_state_ varchar2(64);result_frame_ varchar2(64);
    parity_ varchar2(4000);count_ number;minimum_ number;maximum_ number;
  begin
    select save_lineage into lineage_ from game_sessions where session_token=p_session;
    select command_sha,state_sha,frame_sha into command_sha_,state_sha_,frame_sha_ from tic_commands
      where session_token=p_session and lineage=lineage_ and tic=p_tic and command_seq=p_seq;
    select command_sha into head_command_ from history_heads
      where session_token=p_session and lineage=lineage_;
    select r.state_sha,r.frame_sha,max(case when a.audit_event='PARITY_OK' then a.detail end)
      into result_state_,result_frame_,parity_
      from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
      left join doom_worker_audit a on a.request_id=q.request_id
      where q.session_token=p_session and r.committed_tic=p_tic and r.committed_command_seq=p_seq
      group by r.state_sha,r.frame_sha;
    assert_(head_command_=command_sha_ and state_sha_=result_state_ and frame_sha_=result_frame_
      and parity_ like 'OK|%','lifecycle durable/parity mismatch tic '||p_tic);
    select count(*),coalesce(min(event_ordinal),0),coalesce(max(event_ordinal),-1)
      into count_,minimum_,maximum_ from game_events
      where session_token=p_session and lineage=lineage_ and tic=p_tic;
    assert_(count_=0 or (minimum_=0 and maximum_=count_-1),
      'lifecycle event ordinal gap tic '||p_tic);
  end;

  procedure step_(p_session varchar2,p_seq number,p_use number) is tic_ number;
  begin
    commands_:='{"v":1,"commands":[{"seq":'||p_seq||',"turn":0,"forward":0,'||
      '"strafe":0,"run":0,"fire":0,"use":'||p_use||',"weapon":0,"pause":0,'||
      '"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(p_session,commands_,payload_);
    assert_(payload_ is not null and dbms_lob.getlength(payload_)>0,'empty lifecycle frame');
    select current_tic into tic_ from game_sessions where session_token=p_session;
    assert_(tic_=p_seq,'lifecycle frontier mismatch');assert_integrity_(p_session,tic_,p_seq);
  end;

  procedure stop_wait_(p_session varchar2) is
    deadline_ timestamp with time zone:=systimestamp+interval '30' second;owned_ number;
  begin
    doom_unified_worker.request_stop(p_session);
    loop
      select count(*) into owned_ from doom_worker_control where target_session=p_session;
      exit when owned_=0;
      assert_(systimestamp<=deadline_,'lifecycle worker stop timeout');dbms_session.sleep(.05);
    end loop;
  end;

  procedure retire_(p_session varchar2) is
  begin stop_wait_(p_session);delete from game_sessions where session_token=p_session;commit;end;

  procedure cleanup_ is
    owned_ number;deadline_ timestamp with time zone:=systimestamp+interval '30' second;
  begin
    for i in 1..session_count_ loop
      begin doom_unified_worker.request_stop(sessions_(i));exception when others then null;end;
    end loop;
    loop
      select count(*) into owned_ from doom_worker_control where target_session is not null;
      exit when owned_=0 or systimestamp>deadline_;
      dbms_session.sleep(.05);
    end loop;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_ where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_ where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if old_failpoint_ is not null then update doom_config set number_value=old_failpoint_ where config_key='UNIFIED_WORKER_FAILPOINT';end if;
    if old_split_use_ is not null then update doom_config set number_value=old_split_use_ where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';end if;
    if old_door_speed_ is not null then update doom_config set number_value=old_door_speed_ where config_key='WORLD_DOOR_SPEED';end if;
    if old_lift_speed_ is not null then update doom_config set number_value=old_lift_speed_ where config_key='WORLD_LIFT_SPEED';end if;
    if old_door_wait_ is not null then update doom_config set number_value=old_door_wait_ where config_key='WORLD_DOOR_WAIT';end if;
    if old_lift_wait_ is not null then update doom_config set number_value=old_lift_wait_ where config_key='WORLD_LIFT_WAIT';end if;
    if old_button_tics_ is not null then update doom_config set number_value=old_button_tics_ where config_key='WORLD_BUTTON_TICS';end if;
    for i in 1..session_count_ loop delete from game_sessions where session_token=sessions_(i);end loop;
    commit;
  exception when others then rollback;
  end;

begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  select number_value into old_failpoint_ from doom_config where config_key='UNIFIED_WORKER_FAILPOINT';
  select number_value into old_split_use_ from doom_config where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';
  select number_value into old_door_speed_ from doom_config where config_key='WORLD_DOOR_SPEED';
  select number_value into old_lift_speed_ from doom_config where config_key='WORLD_LIFT_SPEED';
  select number_value into old_door_wait_ from doom_config where config_key='WORLD_DOOR_WAIT';
  select number_value into old_lift_wait_ from doom_config where config_key='WORLD_LIFT_WAIT';
  select number_value into old_button_tics_ from doom_config where config_key='WORLD_BUTTON_TICS';
  update doom_config set number_value=1 where config_key in('UNIFIED_WORKER_ENABLED',
    'UNIFIED_WORKER_PARITY_INTERVAL','UNIFIED_WORKER_SPLIT_USE_ENABLED');
  update doom_config set number_value=1000 where config_key in('WORLD_DOOR_SPEED','WORLD_LIFT_SPEED');
  update doom_config set number_value=1 where config_key='WORLD_DOOR_WAIT';
  update doom_config set number_value=2 where config_key in('WORLD_LIFT_WAIT','WORLD_BUTTON_TICS');
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';commit;

  -- Lift fixture with a static retained MOBJ already resting at the lower
  -- target.  The first attempt is failed after strict apply and must leave no
  -- line, mover, event, ledger, or frontier residue.
  create_session_(62,false,line_,target_,target_x_,target_y_);
  select floor_height,ceiling_height into origin_,ceiling_ from sector_state
    where session_token=session_ and sector_id=target_;
  select min(case when other_floor<origin_ then other_floor end) into bottom_ from (
    select case when rs.sector_id=target_ then lsec.floor_height else rsec.floor_height end other_floor
      from doom_map_linedef l join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join sector_state rsec on rsec.session_token=session_ and rsec.sector_id=rs.sector_id
      join sector_state lsec on lsec.session_token=session_ and lsec.sector_id=ls.sector_id
      where rs.sector_id=target_ or ls.sector_id=target_
  );
  bottom_:=coalesce(bottom_,origin_);
  select min(m.mobj_id) into mobj_ from mobjs m join doom_thing_type_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and m.height>0 and d.category<>'projectile';
  assert_(mobj_ is not null,'no positive-height carry fixture MOBJ');
  update mobjs set x=target_x_,y=target_y_,z=bottom_,sector_id=target_,
    height=least(height,greatest(1,ceiling_-origin_)),awake=0,health=0,
    monster_health_seen=0,death_processed=1,state_tics=1000000,
    state_id=(select d.death_state_id from doom_monster_def d where d.thing_type=mobjs.thing_type)
    where session_token=session_ and mobj_id=mobj_;commit;
  update doom_config set number_value=3 where config_key='UNIFIED_WORKER_FAILPOINT';commit;
  failed_:=false;
  begin step_(session_,1,1);exception when others then failed_:=true;end;
  assert_(failed_,'world failpoint did not reject public step');
  select current_tic into tic_ from game_sessions where session_token=session_;
  select trigger_count into triggers_ from line_state where session_token=session_ and linedef_id=line_;
  select count(*) into count_ from active_movers where session_token=session_;
  assert_(tic_=0 and triggers_=0 and count_=0,'failed USE leaked world/frontier state');
  select count(*) into count_ from active_switches where session_token=session_;
  assert_(count_=0,'failed USE leaked switch state');
  select count(*) into count_ from game_events where session_token=session_ and tic=1;
  assert_(count_=0,'failed USE leaked events');
  select floor_height into height_ from sector_state where session_token=session_ and sector_id=target_;
  assert_(height_=origin_,'failed USE leaked sector height');
  select count(*) into count_ from tic_commands where session_token=session_ and command_seq=1;
  assert_(count_=0,'failed USE leaked tic ledger');
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';commit;
  -- The public request key is deterministic inside one generation. Retire the
  -- terminal FAILED key and retry the same command behind a fresh fence.
  stop_wait_(session_);
  step_(session_,1,1);
  select generation into generation_before_ from doom_worker_control where target_session=session_;
  select direction,timer_tics into direction_,timer_ from active_movers
    where session_token=session_ and sector_id=target_ and plane='FLOOR';
  assert_(direction_=0 and timer_=2,'lift did not lower then enter bounded wait');
  stop_wait_(session_);
  select count(*) into count_ from active_movers where session_token=session_;
  dbms_output.put_line('LIFT_PRE_RESTART_ACTIVE movers='||count_||' session='||session_);
  step_(session_,2,0);
  select generation into generation_after_ from doom_worker_control where target_session=session_;
  assert_(generation_after_>generation_before_,'mid-mover restart did not fence generation');
  select direction,timer_tics into direction_,timer_ from active_movers
    where session_token=session_ and sector_id=target_ and plane='FLOOR';
  select r.world_pack_us,r.world_apply_us,r.prepare_us,r.world_split,r.world_active,r.world_enabled
    into world_pack_us_,world_apply_us_,prepare_us_,world_split_,world_active_,world_enabled_
    from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
    where q.session_token=session_ and r.committed_command_seq=2;
  dbms_output.put_line('LIFT_RESTART_DIAGNOSTIC direction='||direction_||' timer='||timer_||
    ' generation='||generation_before_||'->'||generation_after_||' profile='||
    world_pack_us_||'/'||world_apply_us_||'/'||prepare_us_||' split='||world_split_||
    ' active='||world_active_||' enabled='||world_enabled_);
  assert_(direction_=0 and timer_=1,'restart did not reconstruct lift wait state');
  select count(*) into count_ from active_switches where session_token=session_ and linedef_id=line_;
  assert_(count_=0,'button did not reset on deterministic tic');
  select count(*) into count_ from game_events where session_token=session_ and tic=2
    and event_type='SWITCH_RESET' and number_value=line_;
  assert_(count_=1,'button reset event missing');
  step_(session_,3,0);
  select direction into direction_ from active_movers where session_token=session_ and sector_id=target_ and plane='FLOOR';
  assert_(direction_=1,'lift did not resume upward');
  step_(session_,4,0);
  select count(*) into count_ from active_movers where session_token=session_ and sector_id=target_ and plane='FLOOR';
  select z into height_ from mobjs where session_token=session_ and mobj_id=mobj_;
  assert_(count_=0 and height_=origin_,'lift completion/carry mismatch');
  dbms_output.put_line('retained_use_lift_restart_carry_switch_rollback=PASS line='||line_||
    ' target='||target_||' generation='||generation_before_||'->'||generation_after_);
  retire_(session_);

  -- A tall static retained object makes the non-crushing upward lift stall.
  create_session_(62,false,line_,target_,target_x_,target_y_);
  select floor_height,ceiling_height into origin_,ceiling_ from sector_state
    where session_token=session_ and sector_id=target_;
  select min(case when other_floor<origin_ then other_floor end) into bottom_ from (
    select case when rs.sector_id=target_ then lsec.floor_height else rsec.floor_height end other_floor
      from doom_map_linedef l join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join sector_state rsec on rsec.session_token=session_ and rsec.sector_id=rs.sector_id
      join sector_state lsec on lsec.session_token=session_ and lsec.sector_id=ls.sector_id
      where rs.sector_id=target_ or ls.sector_id=target_
  );
  bottom_:=coalesce(bottom_,origin_);
  select min(m.mobj_id) into mobj_ from mobjs m join doom_thing_type_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and m.height>0 and d.category<>'projectile';
  assert_(mobj_ is not null,'no positive-height blocker fixture MOBJ');
  update mobjs set x=target_x_,y=target_y_,z=bottom_,sector_id=target_,height=ceiling_-bottom_+1,
    awake=0,health=0,monster_health_seen=0,death_processed=1,state_tics=1000000,
    state_id=(select d.death_state_id from doom_monster_def d where d.thing_type=mobjs.thing_type)
    where session_token=session_ and mobj_id=mobj_;commit;
  step_(session_,1,1);step_(session_,2,0);step_(session_,3,0);step_(session_,4,0);
  select count(*) into count_ from game_events where session_token=session_ and tic=4
    and event_type='LIFT_BLOCKED' and number_value=target_;
  select direction into direction_ from active_movers where session_token=session_ and sector_id=target_ and plane='FLOOR';
  select z,height,x,y into bottom_,height_,target_x_,target_y_ from mobjs
    where session_token=session_ and mobj_id=mobj_;
  select sector_id into tic_ from table(doom_bsp_locate(target_x_,target_y_)) where rownum=1;
  select floor_height,ceiling_height into origin_,ceiling_ from sector_state
    where session_token=session_ and sector_id=target_;
  select count(*),coalesce(min(tic),-1) into triggers_,tic_ from game_events
    where session_token=session_ and event_type='LIFT_BLOCKED' and number_value=target_;
  select r.world_split,r.world_active into world_split_,world_active_
    from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
    where q.session_token=session_ and r.committed_command_seq=3;
  dbms_output.put_line('LIFT_BLOCK_DIAGNOSTIC events='||count_||' direction='||direction_||
    ' mobj_z_height='||bottom_||'/'||height_||' xy='||target_x_||'/'||target_y_||
    ' floor_ceiling='||origin_||'/'||ceiling_||' blocked_total_first='||triggers_||'/'||tic_||
    ' split_active='||world_split_||'/'||world_active_||' target='||target_);
  assert_(count_=1 and direction_=1,'retained lift blocker did not stall upward mover');
  dbms_output.put_line('retained_use_lift_blocking=PASS line='||line_||' target='||target_);
  retire_(session_);

  -- Door fixture chooses an initially unoccupied target so the standard
  -- DOOR_RAISE timeline cannot be converted into DOOR_REOPEN by test actors.
  create_session_(1,true,line_,target_,target_x_,target_y_);
  select ceiling_height into origin_ from sector_state where session_token=session_ and sector_id=target_;
  step_(session_,1,1);
  select direction,timer_tics,target_height into direction_,timer_,height_ from active_movers
    where session_token=session_ and sector_id=target_ and plane='CEILING';
  assert_(direction_=0 and timer_=1 and height_>origin_,'door open/wait transition mismatch');
  select count(*) into count_ from game_events where session_token=session_ and tic=1
    and event_type='MOVER_REACHED' and number_value=target_;
  assert_(count_=1,'door open reached event missing');
  step_(session_,2,0);
  select direction into direction_ from active_movers where session_token=session_ and sector_id=target_ and plane='CEILING';
  assert_(direction_=-1,'door did not resume closing');
  select count(*) into count_ from game_events where session_token=session_ and tic=2
    and event_type='MOVER_RESUME' and number_value=target_ and text_value='-1';
  assert_(count_=1,'door close resume event missing');
  step_(session_,3,0);
  select count(*) into count_ from active_movers where session_token=session_ and sector_id=target_ and plane='CEILING';
  select ceiling_height into height_ from sector_state where session_token=session_ and sector_id=target_;
  assert_(count_=0 and height_=origin_,'door did not close to exact origin');
  dbms_output.put_line('retained_use_door_timeline=PASS line='||line_||' target='||target_);
  retire_(session_);

  cleanup_;
  dbms_output.put_line('AUTOREST_WORKER_USE_LIFECYCLE_OK rollback restart carry block switch door parity=SQL');
exception when others then
  declare message_ varchar2(3000):=sqlerrm||' '||dbms_utility.format_error_backtrace;begin
    cleanup_;raise_application_error(-20000,substr('USE lifecycle failed: '||message_,1,1900));end;
end;
/
exit
