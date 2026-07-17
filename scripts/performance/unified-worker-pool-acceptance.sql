whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Bounded two-slot regression: simultaneous residency, interleaved DMSC/v2
-- commits, response correlation, cross-session fencing and independent restart.
declare
  a_ varchar2(32);b_ varchar2(32);la_ varchar2(64);lb_ varchar2(64);
  payload_ blob;ga_ number;gb_ number;ready_ number;map_ varchar2(64);
  error_ varchar2(4000);ta_ number;tb_ number;sa_ number;sb_ number;
  slot_a_ number;slot_b_ number;sid_a_ number;sid_b_ number;old_ga_ number;
  old_enabled_ number;old_wait_ number;old_capacity_ number;status_ varchar2(16);rg_ number;
  ct_ number;cs_ number;dv_ number;dc_ number;ds_ varchar2(64);
  ss_ varchar2(64);fs_ varchar2(64);rb_ number;rs_ varchar2(64);
  delta_ blob;response_ blob;deadline_ timestamp with time zone;count_ number;
  blocked_ boolean;

  function command_(p_seq number,p_forward number default 1) return raw is
  begin
    return hextoraw('444d53430201000000000000'||
      lpad(to_char(p_seq,'fmxxxxxxxx'),8,'0')||'00'||
      case p_forward when -1 then 'ff' when 0 then '00' else '01' end||
      '0000'||'00000000');
  end;
  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;
  procedure step_(p_session varchar2,p_lineage varchar2,p_generation number,
    p_request varchar2,p_tic number,p_seq number,p_wait number) is
  begin
    doom_worker_api.step(p_session,p_lineage,p_generation,p_request,p_tic,p_seq,
      2,1,command_(p_seq+1),p_wait,status_,rg_,ct_,cs_,dv_,dc_,ds_,ss_,fs_,
      rb_,rs_,delta_,response_,error_);
  end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop_all;exception when others then null;end;
    begin
      deadline_:=systimestamp+interval '20' second;
      loop
        select count(*) into count_ from user_scheduler_running_jobs
          where job_name like 'DOOM_UNIFIED_WORKER___';
        exit when count_=0 or systimestamp>deadline_;
        dbms_session.sleep(.05);
      end loop;
    exception when others then null;end;
    if a_ is not null then delete from game_sessions where session_token=a_;end if;
    if b_ is not null then delete from game_sessions where session_token=b_;end if;
    delete from doom_worker_audit where request_id in(
      '20000000000000000000000000000001',
      '20000000000000000000000000000002',
      '20000000000000000000000000000003');
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null,last_error=null;
    update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_wait_ is not null then update doom_config set number_value=old_wait_
      where config_key='UNIFIED_WORKER_WAIT_SECONDS';end if;
    if old_capacity_ is not null then update doom_config set number_value=old_capacity_
      where config_key='MAX_ACTIVE_SESSIONS';end if;
    commit;
  end;
begin
  select number_value into old_enabled_ from doom_config
    where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_wait_ from doom_config
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  select number_value into old_capacity_ from doom_config
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=30
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  update doom_config set number_value=greatest(number_value,128)
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';
  commit;
  doom_api.new_game(3,a_,payload_);doom_api.new_game(3,b_,payload_);
  select save_lineage,current_tic,last_command_seq into la_,ta_,sa_
    from game_sessions where session_token=a_;
  select save_lineage,current_tic,last_command_seq into lb_,tb_,sb_
    from game_sessions where session_token=b_;
  doom_worker_api.claim(a_,ga_,ready_,map_,error_);
  assert_(ready_=1 and error_ is null,'pool claim A');
  doom_worker_api.claim(b_,gb_,ready_,map_,error_);
  assert_(ready_=1 and error_ is null,'pool claim B');
  select worker_slot,worker_sid into slot_a_,sid_a_ from doom_worker_control
    where target_session=a_ and ready=1;
  select worker_slot,worker_sid into slot_b_,sid_b_ from doom_worker_control
    where target_session=b_ and ready=1;
  assert_(slot_a_<>slot_b_ and sid_a_<>sid_b_,'pool slot/SID isolation');

  step_(a_,la_,ga_,'20000000000000000000000000000001',ta_,sa_,0);
  step_(b_,lb_,gb_,'20000000000000000000000000000002',tb_,sb_,0);
  deadline_:=systimestamp+interval '30' second;
  loop
    step_(a_,la_,ga_,'20000000000000000000000000000001',ta_,sa_,1);
    exit when status_='COMMITTED';
    assert_(status_ in('QUEUED','PROCESSING'),'pool A terminal '||status_);
    assert_(systimestamp<deadline_,'pool A response timeout');
  end loop;
  assert_(ct_=ta_+1 and cs_=sa_+1 and rg_=ga_,'pool A correlation');
  loop
    step_(b_,lb_,gb_,'20000000000000000000000000000002',tb_,sb_,1);
    exit when status_='COMMITTED';
    assert_(status_ in('QUEUED','PROCESSING'),'pool B terminal '||status_);
    assert_(systimestamp<deadline_,'pool B response timeout');
  end loop;
  assert_(ct_=tb_+1 and cs_=sb_+1 and rg_=gb_,'pool B correlation');
  select count(*) into count_ from doom_worker_request r
    join doom_worker_result x on x.request_id=r.request_id
    where (r.request_id='20000000000000000000000000000001' and
           r.session_token=a_ and x.committed_tic=ta_+1) or
          (r.request_id='20000000000000000000000000000002' and
           r.session_token=b_ and x.committed_tic=tb_+1);
  assert_(count_=2,'pool durable response correlation');

  blocked_:=false;
  begin
    step_(a_,lb_,ga_,'20000000000000000000000000000003',ta_+1,sa_+1,0);
  exception when others then
    if sqlcode=-20721 then blocked_:=true;else raise;end if;
  end;
  assert_(blocked_,'cross-session lineage accepted');

  old_ga_:=ga_;
  doom_unified_worker.request_stop(a_);
  deadline_:=systimestamp+interval '30' second;
  loop
    select count(*) into count_ from doom_worker_control where target_session=a_;
    exit when count_=0;
    assert_(systimestamp<deadline_,'pool A stop timeout');
    dbms_session.sleep(.05);
  end loop;
  select generation,ready into ct_,ready_ from doom_worker_control
    where target_session=b_;
  assert_(ct_=gb_ and ready_=1,'pool B changed during A restart');
  doom_worker_api.claim(a_,ga_,ready_,map_,error_);
  assert_(ready_=1 and ga_>old_ga_ and error_ is null,'pool A generation restart');
  select generation,ready into ct_,ready_ from doom_worker_control
    where target_session=b_;
  assert_(ct_=gb_ and ready_=1,'pool B generation independence');

  dbms_output.put_line('UNIFIED_WORKER_POOL_ACCEPTANCE_OK slots='||
    slot_a_||','||slot_b_||' generations='||ga_||','||gb_);
  cleanup_;
exception when others then
  error_:=sqlerrm||' '||dbms_utility.format_error_backtrace;
  cleanup_;
  raise_application_error(-20000,substr(error_,1,1900));
end;
/

exit
