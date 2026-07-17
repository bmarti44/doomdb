whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Deterministic public-path gate for the retained USE split.  Fixtures are
-- selected from immutable map geometry and special semantics; no route line
-- or player outcome is hard-coded.  Every committed action must retain the
-- SQL oracle's canonical state/frame result and durable history chains.
declare
  type token_tab is table of varchar2(32) index by pls_integer;
  sessions_ token_tab;session_count_ pls_integer:=0;
  session_ varchar2(32);payload_ blob;commands_ clob;
  old_enabled_ number;old_parity_ number;old_split_use_ number;
  line_ number;target_ number;denied_ number;triggers_ number;movers_ number;

  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;

  procedure remember_(p_session varchar2) is
  begin session_count_:=session_count_+1;sessions_(session_count_):=p_session;end;

  procedure fixture_(
    p_special number,p_walk boolean,
    p_line out number,p_x out number,p_y out number,p_angle out number,
    p_sector out number,p_target_sector out number
  ) is
    length_ number;distance_ number:=case when p_walk then 2 else 8 end;
    mid_x_ number;mid_y_ number;target_x_ number;target_y_ number;
  begin
    p_line:=null;p_target_sector:=null;
    for candidate_ in (
      select ml.linedef_id,ml.tag,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
             ls.sector_id left_sector
        from doom_map_linedef ml
        join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
        join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
        left join doom_map_sidedef ls on ls.sidedef_id=ml.left_sidedef_id
        join doom_linedef_special_def d on d.special_id=ml.special
       where ml.special=p_special
         and instr(d.semantics,case when p_walk then 'WALK|' else 'USE|' end)=1
       order by ml.linedef_id
    ) loop
      length_:=sqrt(power(candidate_.x2-candidate_.x1,2)+
                    power(candidate_.y2-candidate_.y1,2));
      if length_=0 then continue;end if;
      mid_x_:=(candidate_.x1+candidate_.x2)/2;
      mid_y_:=(candidate_.y1+candidate_.y2)/2;
      -- Negative determinant is the actionable/right side used by the SQL
      -- oracle.  WALK starts close enough that one normal forward tic crosses.
      p_x:=mid_x_+(candidate_.y2-candidate_.y1)*distance_/length_;
      p_y:=mid_y_-(candidate_.x2-candidate_.x1)*distance_/length_;
      target_x_:=mid_x_-(candidate_.y2-candidate_.y1)*2/length_;
      target_y_:=mid_y_+(candidate_.x2-candidate_.x1)*2/length_;
      p_angle:=mod(round(atan2(mid_y_-p_y,mid_x_-p_x)*180/acos(-1)/5.625)*5.625+360,360);
      begin
        select sector_id into p_sector from table(doom_bsp_locate(p_x,p_y)) where rownum=1;
        if candidate_.tag<>0 then
          select min(sector_id) into p_target_sector from doom_map_sector where tag=candidate_.tag;
        else
          p_target_sector:=candidate_.left_sector;
        end if;
        -- A two-sided crossing fixture must actually enter the selected target
        -- side; this closes false positives caused by nearby BSP boundaries.
        if p_walk then
          declare located_ number;begin
            select sector_id into located_ from table(doom_bsp_locate(target_x_,target_y_)) where rownum=1;
            if p_target_sector is not null then assert_(located_=p_target_sector,
              'WALK target-side fixture mismatch special '||p_special);end if;
          end;
        end if;
        p_line:=candidate_.linedef_id;exit;
      exception when no_data_found then null;end;
    end loop;
    assert_(p_line is not null,'no geometry fixture for special '||p_special);
  end;

  procedure new_fixture_session_(
    p_special number,p_walk boolean,p_blue number,
    p_line out number,p_target_sector out number
  ) is
    x_ number;y_ number;angle_ number;sector_ number;
  begin
    fixture_(p_special,p_walk,p_line,x_,y_,angle_,sector_,p_target_sector);
    doom_api.new_game(3,session_,payload_);remember_(session_);
    update players set x=x_,y=y_,angle=angle_,
      z=(select floor_height from sector_state where session_token=session_ and sector_id=sector_),
      blue_key=p_blue
     where session_token=session_ and player_id=(
       select current_player_id from game_sessions where session_token=session_);
    commit;
  end;

  procedure assert_integrity_(p_session varchar2,p_tic number,p_seq number) is
    lineage_ varchar2(64);command_sha_ varchar2(64);state_sha_ varchar2(64);
    frame_sha_ varchar2(64);head_command_ varchar2(64);head_event_ varchar2(64);
    result_state_ varchar2(64);result_frame_ varchar2(64);parity_ varchar2(4000);
    count_ number;minimum_ number;maximum_ number;distinct_ number;referenced_ number;
  begin
    select save_lineage into lineage_ from game_sessions where session_token=p_session;
    select command_sha,state_sha,frame_sha into command_sha_,state_sha_,frame_sha_
      from tic_commands where session_token=p_session and lineage=lineage_ and
        tic=p_tic and command_ordinal=0 and command_seq=p_seq;
    select command_sha,event_sha into head_command_,head_event_ from history_heads
      where session_token=p_session and lineage=lineage_;
    assert_(head_command_=command_sha_,'command history head mismatch tic '||p_tic);
    select r.state_sha,r.frame_sha,max(case when a.audit_event='PARITY_OK' then a.detail end)
      into result_state_,result_frame_,parity_
      from doom_worker_request q join doom_worker_result r on r.request_id=q.request_id
      left join doom_worker_audit a on a.request_id=q.request_id
     where q.session_token=p_session and r.committed_tic=p_tic and
           r.committed_command_seq=p_seq
     group by r.state_sha,r.frame_sha;
    assert_(state_sha_=result_state_ and frame_sha_=result_frame_ and
      regexp_like(state_sha_,'^[0-9a-f]{64}$') and regexp_like(frame_sha_,'^[0-9a-f]{64}$'),
      'state/frame durable mismatch tic '||p_tic);
    assert_(parity_ like 'OK|%','missing state/frame SQL parity tic '||p_tic);
    select count(*),coalesce(min(event_ordinal),0),coalesce(max(event_ordinal),-1),
           count(distinct event_ordinal)
      into count_,minimum_,maximum_,distinct_
      from game_events where session_token=p_session and lineage=lineage_ and tic=p_tic;
    assert_(count_=0 or (minimum_=0 and maximum_=count_-1 and distinct_=count_),
      'non-contiguous event ordinals tic '||p_tic);
    if head_event_<>rpad('0',64,'0') then
      select count(*) into referenced_ from (
        select event_sha from game_events where session_token=p_session and lineage=lineage_
        union all
        select event_sha from audio_events where session_token=p_session and lineage=lineage_
      ) where event_sha=head_event_;
      assert_(referenced_=1,'event history head not present exactly once tic '||p_tic);
    end if;
  end;

  procedure step_(p_session varchar2,p_seq number,p_forward number,p_use number) is
    tic_ number;
  begin
    commands_:='{"v":1,"commands":[{"seq":'||p_seq||',"turn":0,"forward":'||p_forward||
      ',"strafe":0,"run":0,"fire":0,"use":'||p_use||',"weapon":0,"pause":0,'||
      '"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(p_session,commands_,payload_);
    assert_(payload_ is not null and dbms_lob.getlength(payload_)>0,'empty USE frame seq '||p_seq);
    select current_tic into tic_ from game_sessions where session_token=p_session;
    assert_(tic_=p_seq,'unexpected one-command frontier seq '||p_seq);
    assert_integrity_(p_session,tic_,p_seq);
  end;

  procedure retire_(p_session varchar2) is
    deadline_ timestamp with time zone:=systimestamp+interval '30' second;owned_ number;
  begin
    doom_unified_worker.request_stop(p_session);
    loop
      select count(*) into owned_ from doom_worker_control where target_session=p_session;
      exit when owned_=0;
      assert_(systimestamp<=deadline_,'worker stop timeout for matrix fixture');
      dbms_session.sleep(.05);
    end loop;
    delete from game_sessions where session_token=p_session;commit;
  end;

  procedure cleanup_ is
  begin
    for i in 1..session_count_ loop
      begin doom_unified_worker.request_stop(sessions_(i));exception when others then null;end;
    end loop;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if old_split_use_ is not null then update doom_config set number_value=old_split_use_
      where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';end if;
    for i in 1..session_count_ loop delete from game_sessions where session_token=sessions_(i);end loop;
    commit;
  exception when others then rollback;
  end;

  procedure prove_(p_special number,p_walk boolean,p_blue number default 0) is
    line_ number;target_ number;triggers_ number;movers_ number;events_ number;status_ varchar2(16);
    before_x_ number;before_y_ number;after_x_ number;after_y_ number;
  begin
    new_fixture_session_(p_special,p_walk,p_blue,line_,target_);
    select p.x,p.y into before_x_,before_y_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id
      where g.session_token=session_;
    step_(session_,1,case when p_walk then 1 else 0 end,case when p_walk then 0 else 1 end);
    select p.x,p.y into after_x_,after_y_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id
      where g.session_token=session_;
    select trigger_count into triggers_ from line_state where session_token=session_ and linedef_id=line_;
    select count(*) into movers_ from active_movers where session_token=session_ and source_linedef_id=line_;
    select count(*) into events_ from game_events where session_token=session_ and tic=1 and
      event_type='LINE_TRIGGER' and number_value=line_ and text_value=to_char(p_special);
    select map_status into status_ from game_sessions where session_token=session_;
    if triggers_<>1 or events_<>1 then
      dbms_output.put_line('USE_MATRIX_TRIGGER_DIAGNOSTIC special='||p_special||' line='||line_||
        ' before='||before_x_||','||before_y_||' after='||after_x_||','||after_y_||
        ' triggers/events='||triggers_||'/'||events_);
    end if;
    assert_(triggers_=1 and events_=1,'special did not trigger exactly once '||p_special);
    if p_special=11 then assert_(status_='COMPLETED','exit special did not complete map');
    else assert_(movers_>0,'special produced no mover '||p_special);end if;
    dbms_output.put_line('retained_use_special_'||p_special||'=PASS line='||line_||
      ' target='||coalesce(to_char(target_),'NONE')||' movers='||movers_);
    retire_(session_);
  end;

begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  select number_value into old_split_use_ from doom_config where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';
  update doom_config set number_value=1 where config_key in('UNIFIED_WORKER_ENABLED',
    'UNIFIED_WORKER_SPLIT_USE_ENABLED');
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  commit;

  prove_(1,false);prove_(11,false);prove_(62,false);prove_(88,true);prove_(117,false);

  -- Blue door denial and grant are separate freshly loaded retained owners;
  -- no out-of-band player mutation is hidden between retained tics.
  new_fixture_session_(26,false,0,line_,target_);step_(session_,1,0,1);
  select count(*) into denied_ from game_events where session_token=session_ and tic=1 and
    event_type='KEY_DENIED' and number_value=line_ and text_value='BLUE';
  select trigger_count into triggers_ from line_state where session_token=session_ and linedef_id=line_;
  select count(*) into movers_ from active_movers where session_token=session_ and source_linedef_id=line_;
  assert_(denied_=1 and triggers_=0 and movers_=0,'blue-key denial mutated door state');
  dbms_output.put_line('retained_use_special_26_deny=PASS line='||line_);
  retire_(session_);
  prove_(26,false,1);

  cleanup_;
  dbms_output.put_line('AUTOREST_WORKER_USE_MATRIX_OK specials=1,11,26,62,88,117 parity=SQL');
exception when others then
  declare message_ varchar2(3000):=sqlerrm||' '||dbms_utility.format_error_backtrace;begin
    cleanup_;raise_application_error(-20000,substr('USE matrix failed: '||message_,1,1900));end;
end;
/
exit
