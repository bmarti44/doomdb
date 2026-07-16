whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Production-shaped transaction/rendezvous probe for the unified retained
-- worker.  The actor delta is not yet unified, so this gate persists the real
-- DMSD/v1 one-command turn delta.  All lifecycle, fencing, idempotency,
-- rollback/discard, commit/accept, generation rollover and restart behavior is
-- real.  Every object is disposable and deliberately absent from bootstrap.

begin
  begin dbms_scheduler.drop_job('DOOM_UTX_PROBE_JOB',true); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_UTX_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_UTX_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_UTX_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_UTX_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_UTX_REQUEST_QT',true); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_UTX_RESPONSE_QT',true); exception when others then null; end;
  begin execute immediate 'drop package doom_utx_probe'; exception when others then null; end;
  begin execute immediate 'drop table doom_utx_audit purge'; exception when others then null; end;
  begin execute immediate 'drop table doom_utx_result purge'; exception when others then null; end;
  begin execute immediate 'drop table doom_utx_request purge'; exception when others then null; end;
  begin execute immediate 'drop table doom_utx_control purge'; exception when others then null; end;
end;
/

create table doom_utx_control (
  singleton number(1) primary key check(singleton=1),
  target_session varchar2(32) not null,
  target_lineage varchar2(64) not null,
  generation number(12) not null check(generation>=0),
  ready number(1) not null check(ready in(0,1)),
  stop_requested number(1) not null check(stop_requested in(0,1)),
  worker_sid number,
  heartbeat timestamp with time zone,
  last_error varchar2(4000)
);

create table doom_utx_request (
  request_id varchar2(32) primary key,
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  generation number(12) not null,
  expected_tic number(12) not null,
  expected_command_seq number(12) not null,
  command_pack raw(2000) not null,
  command_sha varchar2(64) not null,
  fault_mode varchar2(16),
  request_status varchar2(16) not null,
  response_generation number(12),
  error_text varchar2(4000),
  created_at timestamp with time zone not null,
  completed_at timestamp with time zone,
  constraint doom_utx_request_token_ck check(regexp_like(request_id,'^[0-9a-f]{32}$')),
  constraint doom_utx_request_session_ck check(regexp_like(session_token,'^[0-9a-f]{32}$')),
  constraint doom_utx_request_lineage_ck check(regexp_like(save_lineage,'^[0-9a-f]{64}$')),
  constraint doom_utx_request_frontier_ck check(
    generation>0 and expected_tic>=0 and expected_command_seq>=0),
  constraint doom_utx_request_status_ck check(
    request_status in('QUEUED','PROCESSING','COMMITTED','FAILED')),
  constraint doom_utx_request_fault_ck check(
    fault_mode is null or fault_mode in('BAD_MAGIC','BAD_COUNT','BAD_LENGTH','PRECOMMIT','ACCEPT')),
  constraint doom_utx_request_command_sha_ck check(regexp_like(command_sha,'^[0-9a-f]{64}$'))
);

create table doom_utx_result (
  request_id varchar2(32) primary key,
  committed_tic number(12) not null,
  committed_command_seq number(12) not null,
  delta_version number(3) not null,
  delta_count number(3) not null,
  delta_bytes number(5) not null,
  delta_sha varchar2(64) not null,
  delta_pack raw(2000) not null,
  response_blob blob not null,
  constraint doom_utx_result_request_fk foreign key(request_id)
    references doom_utx_request(request_id) on delete cascade,
  constraint doom_utx_result_sha_ck check(regexp_like(delta_sha,'^[0-9a-f]{64}$'))
) lob(response_blob) store as securefile(cache);

create table doom_utx_audit (
  audit_id number generated always as identity primary key,
  request_id varchar2(32),
  generation number(12),
  audit_event varchar2(32) not null,
  detail varchar2(4000),
  created_at timestamp with time zone default systimestamp not null
);

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,l_session,l_payload);
  select save_lineage into l_lineage from game_sessions where session_token=l_session;
  insert into doom_utx_control(singleton,target_session,target_lineage,generation,
    ready,stop_requested) values(1,l_session,l_lineage,0,0,0);
  commit;
end;
/

begin
  dbms_aqadm.create_queue_table('DOOM_UTX_REQUEST_QT','RAW');
  dbms_aqadm.create_queue_table('DOOM_UTX_RESPONSE_QT','RAW');
  dbms_aqadm.create_queue('DOOM_UTX_REQUEST_Q','DOOM_UTX_REQUEST_QT');
  dbms_aqadm.create_queue('DOOM_UTX_RESPONSE_Q','DOOM_UTX_RESPONSE_QT');
  dbms_aqadm.start_queue('DOOM_UTX_REQUEST_Q');
  dbms_aqadm.start_queue('DOOM_UTX_RESPONSE_Q');
end;
/

create or replace package doom_utx_probe authid definer as
  procedure run;
  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_request in varchar2,p_expected_tic in number,p_expected_seq in number,
    p_command in raw,p_fault in varchar2,
    p_status out varchar2,p_response_generation out number,
    p_committed_tic out number,p_committed_seq out number,p_delta_sha out varchar2);
  procedure request_stop;
end doom_utx_probe;
/

create or replace package body doom_utx_probe as
  c_magic constant varchar2(8):='444D5344';

  procedure audit_event(
    p_request varchar2,p_generation number,p_event varchar2,p_detail varchar2 default null
  ) is
    pragma autonomous_transaction;
  begin
    insert into doom_utx_audit(request_id,generation,audit_event,detail)
      values(p_request,p_generation,p_event,substr(p_detail,1,4000));
    commit;
  exception when others then rollback;
  end;

  procedure terminal_failure(
    p_request varchar2,p_generation number,p_error varchar2
  ) is
    pragma autonomous_transaction;
  begin
    update doom_utx_request set request_status='FAILED',
      response_generation=p_generation,error_text=substr(p_error,1,4000),
      completed_at=systimestamp
      where request_id=p_request and request_status in('QUEUED','PROCESSING');
    commit;
  end;

  procedure submit_request(
    p_session varchar2,p_lineage varchar2,p_generation number,p_request varchar2,
    p_expected_tic number,p_expected_seq number,p_command raw,p_fault varchar2,
    p_status out varchar2
  ) is
    pragma autonomous_transaction;
    l_enq dbms_aq.enqueue_options_t;l_props dbms_aq.message_properties_t;
    l_msgid raw(16);l_payload raw(32767);l_sha varchar2(64);
    l_session varchar2(32);l_lineage varchar2(64);l_generation number;
    l_tic number;l_seq number;l_command raw(32767);l_fault varchar2(16);
  begin
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') or
       p_lineage is null or not regexp_like(p_lineage,'^[0-9a-f]{64}$') or
       p_request is null or not regexp_like(p_request,'^[0-9a-f]{32}$') or
       p_generation<1 or p_expected_tic<0 or p_expected_seq<0 or
       p_command is null or utl_raw.length(p_command)>2000 or
       (p_fault is not null and p_fault not in
         ('BAD_MAGIC','BAD_COUNT','BAD_LENGTH','PRECOMMIT','ACCEPT')) then
      raise_application_error(-20000,'invalid unified worker request');
    end if;
    select lower(rawtohex(standard_hash(p_command,'SHA256'))) into l_sha from dual;
    begin
      insert into doom_utx_request(request_id,session_token,save_lineage,generation,
        expected_tic,expected_command_seq,command_pack,command_sha,fault_mode,
        request_status,created_at)
      values(p_request,p_session,p_lineage,p_generation,p_expected_tic,p_expected_seq,
        p_command,l_sha,p_fault,'QUEUED',systimestamp);
      l_enq.visibility:=dbms_aq.immediate;l_props.correlation:=p_request;
      l_payload:=utl_raw.cast_to_raw(p_request);
      dbms_aq.enqueue('DOOM_UTX_REQUEST_Q',l_enq,l_props,l_payload,l_msgid);
      p_status:='QUEUED';commit;
    exception when dup_val_on_index then
      select session_token,save_lineage,generation,expected_tic,expected_command_seq,
        command_pack,fault_mode,request_status
        into l_session,l_lineage,l_generation,l_tic,l_seq,l_command,l_fault,p_status
        from doom_utx_request where request_id=p_request;
      if l_session<>p_session or l_lineage<>p_lineage or l_generation<>p_generation or
         l_tic<>p_expected_tic or l_seq<>p_expected_seq or
         utl_raw.compare(l_command,p_command)<>0 or
         coalesce(l_fault,'-')<>coalesce(p_fault,'-') then
        raise_application_error(-20000,'conflicting duplicate request');
      end if;
      commit;
    end;
  end;

  function small_u64(p_raw raw,p_offset number) return number is
    l_low number;
  begin
    if rawtohex(utl_raw.substr(p_raw,p_offset,4))<>'00000000' then
      raise_application_error(-20000,'frontier exceeds v1 probe range');
    end if;
    l_low:=utl_raw.cast_to_binary_integer(
      utl_raw.substr(p_raw,p_offset+4,4),utl_raw.big_endian);
    if l_low<0 then raise_application_error(-20000,'negative v1 frontier');end if;
    return l_low;
  end;

  procedure validate_delta(
    p_delta raw,p_expected_tic number,p_expected_seq number,
    p_tic out number,p_seq out number,p_angle out binary_double
  ) is
  begin
    if p_delta is null or utl_raw.length(p_delta)<>32 then
      raise_application_error(-20000,'DMSD/v1 length');
    end if;
    if rawtohex(utl_raw.substr(p_delta,1,8))<>'444D534401000100' then
      raise_application_error(-20000,'DMSD/v1 header/count');
    end if;
    p_seq:=small_u64(p_delta,9);p_tic:=small_u64(p_delta,17);
    p_angle:=utl_raw.cast_to_binary_double(
      utl_raw.substr(p_delta,25,8),utl_raw.big_endian);
    if p_seq<>p_expected_seq+1 or p_tic<>p_expected_tic+1 or
       p_angle<0d or p_angle>=360d then
      raise_application_error(-20000,'DMSD/v1 frontier/domain');
    end if;
  end;

  procedure load_generation(p_generation number) is
    l_session varchar2(32);l_lineage varchar2(64);l_tic number;l_seq number;
    l_x number;l_y number;l_z number;l_angle binary_double;l_result varchar2(4000);
  begin
    select c.target_session,c.target_lineage,g.current_tic,g.last_command_seq,
      p.x,p.y,p.z,to_binary_double(p.angle)
      into l_session,l_lineage,l_tic,l_seq,l_x,l_y,l_z,l_angle
      from doom_utx_control c join game_sessions g
        on g.session_token=c.target_session
      join players p on p.session_token=g.session_token
        and p.player_id=g.current_player_id
      where c.singleton=1 and c.generation=p_generation;
    l_result:=doom_resident_sim_load_exact_player(l_session,l_lineage,p_generation,
      l_tic,l_seq,l_x,l_y,l_z,l_angle);
    if l_result<>'OK' then raise_application_error(-20000,l_result);end if;
  end;

  procedure reconstruct(
    p_request varchar2,p_old_generation number,p_reason varchar2,
    p_new_generation out number
  ) is
  begin
    select generation into p_new_generation from doom_utx_control
      where singleton=1 for update;
    if p_new_generation<>p_old_generation then
      raise_application_error(-20000,'reconstruction generation moved');
    end if;
    p_new_generation:=p_new_generation+1;
    update doom_utx_control set generation=p_new_generation,ready=0,
      last_error=substr(p_reason,1,4000),heartbeat=systimestamp where singleton=1;
    commit;
    load_generation(p_new_generation);
    update doom_utx_control set ready=1,last_error=null,heartbeat=systimestamp
      where singleton=1 and generation=p_new_generation;
    update doom_utx_request set response_generation=p_new_generation
      where request_id=p_request;
    commit;
    audit_event(p_request,p_new_generation,'RECONSTRUCT',p_reason);
  end;

  procedure respond(p_request varchar2) is
    l_enq dbms_aq.enqueue_options_t;l_props dbms_aq.message_properties_t;
    l_msgid raw(16);l_payload raw(32767);
  begin
    l_enq.visibility:=dbms_aq.immediate;l_props.correlation:=p_request;
    l_payload:=utl_raw.cast_to_raw(p_request);
    dbms_aq.enqueue('DOOM_UTX_RESPONSE_Q',l_enq,l_props,l_payload,l_msgid);
  end;

  procedure process_request(p_request varchar2,p_worker_generation in out number) is
    l_session varchar2(32);l_lineage varchar2(64);l_generation number;
    l_expected_tic number;l_expected_seq number;l_command raw(32767);
    l_fault varchar2(16);l_status varchar2(16);l_target_session varchar2(32);
    l_target_lineage varchar2(64);l_ready number;l_db_lineage varchar2(64);
    l_db_tic number;l_db_seq number;l_delta raw(32767);l_delta_tic number;
    l_delta_seq number;l_angle binary_double;l_result varchar2(4000);
    l_response blob;l_prepared boolean:=false;l_committed boolean:=false;
    l_error varchar2(4000);l_recovered_generation number;
  begin
    select session_token,save_lineage,generation,expected_tic,expected_command_seq,
      command_pack,fault_mode,request_status
      into l_session,l_lineage,l_generation,l_expected_tic,l_expected_seq,
        l_command,l_fault,l_status
      from doom_utx_request where request_id=p_request for update;
    if l_status in('COMMITTED','FAILED') then rollback;return;end if;
    update doom_utx_request set request_status='PROCESSING' where request_id=p_request;

    select target_session,target_lineage,generation,ready
      into l_target_session,l_target_lineage,p_worker_generation,l_ready
      from doom_utx_control where singleton=1 for update;
    if l_ready<>1 or l_generation<>p_worker_generation or
       l_session<>l_target_session or l_lineage<>l_target_lineage then
      raise_application_error(-20000,'worker control fence');
    end if;
    select save_lineage,current_tic,last_command_seq
      into l_db_lineage,l_db_tic,l_db_seq from game_sessions
      where session_token=l_session for update;
    if l_db_lineage<>l_lineage or l_db_tic<>l_expected_tic or
       l_db_seq<>l_expected_seq then
      raise_application_error(-20000,'database frontier fence');
    end if;

    l_delta:=doom_resident_sim_step_turn_batch(l_session,l_lineage,l_generation,
      p_request,l_command);
    l_prepared:=true;
    -- The legacy DMSD bridge returns its 104-byte reusable capacity buffer.
    -- The unified API must return exact length; adapt the bounded one-record
    -- legacy result here so this probe can enforce that production contract.
    l_delta:=utl_raw.substr(l_delta,1,32);
    if l_fault='BAD_MAGIC' then
      l_delta:=utl_raw.overlay(hextoraw('00000000'),l_delta,1,4);
    elsif l_fault='BAD_COUNT' then
      l_delta:=utl_raw.overlay(hextoraw('02'),l_delta,7,1);
    elsif l_fault='BAD_LENGTH' then
      l_delta:=utl_raw.substr(l_delta,1,31);
    end if;
    validate_delta(l_delta,l_expected_tic,l_expected_seq,l_delta_tic,l_delta_seq,l_angle);
    if l_fault='PRECOMMIT' then raise_application_error(-20000,'injected precommit failure');end if;

    update players set angle=l_angle where session_token=l_session and player_id=(
      select current_player_id from game_sessions where session_token=l_session);
    if sql%rowcount<>1 then raise_application_error(-20000,'player persistence rowcount');end if;
    update game_sessions set current_tic=l_delta_tic,last_command_seq=l_delta_seq
      where session_token=l_session and current_tic=l_expected_tic
        and last_command_seq=l_expected_seq and save_lineage=l_lineage;
    if sql%rowcount<>1 then raise_application_error(-20000,'session persistence rowcount');end if;
    insert into doom_utx_result(request_id,committed_tic,committed_command_seq,
      delta_version,delta_count,delta_bytes,delta_sha,delta_pack,response_blob)
    values(p_request,l_delta_tic,l_delta_seq,1,1,utl_raw.length(l_delta),
      lower(rawtohex(standard_hash(l_delta,'SHA256'))),l_delta,empty_blob())
      returning response_blob into l_response;
    dbms_lob.writeappend(l_response,2,utl_raw.cast_to_raw('OK'));
    update doom_utx_request set request_status='COMMITTED',
      response_generation=l_generation,completed_at=systimestamp,error_text=null
      where request_id=p_request;
    commit;l_committed:=true;
    audit_event(p_request,l_generation,'COMMIT','tic='||l_delta_tic||' seq='||l_delta_seq);

    if l_fault='ACCEPT' then
      l_result:=doom_resident_sim_accept(l_session,l_lineage,l_generation,
        'ffffffffffffffffffffffffffffffff');
    else
      l_result:=doom_resident_sim_accept(l_session,l_lineage,l_generation,p_request);
    end if;
    if l_result<>'OK' then
      reconstruct(p_request,l_generation,'postcommit accept: '||l_result,
        l_recovered_generation);
      p_worker_generation:=l_recovered_generation;
    else
      audit_event(p_request,l_generation,'ACCEPT');
    end if;
  exception when others then
    l_error:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    if not l_committed then
      rollback;
      if l_prepared then
        l_result:=doom_resident_sim_discard(l_session,l_lineage,l_generation,p_request);
        if l_result='OK' then
          audit_event(p_request,l_generation,'DISCARD',l_error);
        else
          begin
            reconstruct(p_request,l_generation,'discard failure: '||l_result,
              l_recovered_generation);
            p_worker_generation:=l_recovered_generation;
          exception when others then null;end;
        end if;
      end if;
      terminal_failure(p_request,p_worker_generation,l_error);
    end if;
  end;

  procedure run is
    l_deq dbms_aq.dequeue_options_t;l_props dbms_aq.message_properties_t;
    l_payload raw(32767);l_msgid raw(16);l_request varchar2(32);
    l_generation number;l_stop number:=0;l_failure varchar2(4000);
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    select generation into l_generation from doom_utx_control
      where singleton=1 for update;
    l_generation:=l_generation+1;
    update doom_utx_control set generation=l_generation,ready=0,
      worker_sid=sys_context('USERENV','SID'),heartbeat=systimestamp,last_error=null
      where singleton=1;
    commit;
    load_generation(l_generation);
    update doom_utx_control set ready=1,heartbeat=systimestamp where singleton=1;
    commit;audit_event(null,l_generation,'WORKER_READY');
    l_deq.wait:=1;l_deq.visibility:=dbms_aq.immediate;
    l_deq.navigation:=dbms_aq.first_message;
    loop
      begin
        dbms_aq.dequeue('DOOM_UTX_REQUEST_Q',l_deq,l_props,l_payload,l_msgid);
        l_request:=utl_raw.cast_to_varchar2(l_payload);
        process_request(l_request,l_generation);
        update doom_utx_control set heartbeat=systimestamp where singleton=1;
        commit;respond(l_request);
      exception when no_messages then null;
      end;
      select stop_requested into l_stop from doom_utx_control where singleton=1;
      exit when l_stop=1;
    end loop;
    update doom_utx_control set ready=0,heartbeat=systimestamp where singleton=1;
    commit;audit_event(null,l_generation,'WORKER_STOP');
  exception when others then
    l_failure:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    begin
      update doom_utx_control set ready=0,stop_requested=1,
        last_error=l_failure,heartbeat=systimestamp where singleton=1;
      commit;audit_event(null,l_generation,'WORKER_FATAL',l_failure);
    exception when others then null;end;
  end;

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_request in varchar2,p_expected_tic in number,p_expected_seq in number,
    p_command in raw,p_fault in varchar2,
    p_status out varchar2,p_response_generation out number,
    p_committed_tic out number,p_committed_seq out number,p_delta_sha out varchar2
  ) is
    l_status varchar2(16);l_deq dbms_aq.dequeue_options_t;
    l_props dbms_aq.message_properties_t;l_payload raw(32767);l_msgid raw(16);
    l_error varchar2(4000);
  begin
    submit_request(p_session,p_lineage,p_generation,p_request,p_expected_tic,
      p_expected_seq,p_command,p_fault,l_status);
    if l_status not in('COMMITTED','FAILED') then
      l_deq.wait:=10;l_deq.visibility:=dbms_aq.immediate;
      l_deq.navigation:=dbms_aq.first_message;l_deq.correlation:=p_request;
      begin
        dbms_aq.dequeue('DOOM_UTX_RESPONSE_Q',l_deq,l_props,l_payload,l_msgid);
      exception when others then
        if sqlcode<>-25228 then raise;end if;
      end;
    end if;
    select request_status,response_generation,error_text
      into l_status,p_response_generation,l_error
      from doom_utx_request where request_id=p_request;
    if l_status='COMMITTED' then
      select committed_tic,committed_command_seq,delta_sha
        into p_committed_tic,p_committed_seq,p_delta_sha
        from doom_utx_result where request_id=p_request;
      p_status:='COMMITTED';
    elsif l_status='FAILED' then
      p_committed_tic:=null;p_committed_seq:=null;p_delta_sha:=null;
      p_status:='FAILED|'||l_error;
    else
      raise_application_error(-20000,'worker rendezvous timeout: '||l_status);
    end if;
  end;

  procedure request_stop is
    pragma autonomous_transaction;
  begin
    update doom_utx_control set stop_requested=1 where singleton=1;commit;
  end;
end doom_utx_probe;
/

begin
  dbms_scheduler.create_job(job_name=>'DOOM_UTX_PROBE_JOB',
    job_type=>'STORED_PROCEDURE',job_action=>'DOOM_UTX_PROBE.RUN',
    start_date=>systimestamp,enabled=>true,auto_drop=>false);
end;
/

declare
  l_ready number;l_error varchar2(4000);
  l_deadline timestamp with time zone:=systimestamp+interval '20' second;
begin
  loop
    select ready,last_error into l_ready,l_error from doom_utx_control where singleton=1;
    if l_error is not null then raise_application_error(-20000,l_error);end if;
    exit when l_ready=1;
    if systimestamp>l_deadline then raise_application_error(-20000,'worker start timeout');end if;
    dbms_session.sleep(.05);
  end loop;
end;
/

-- Normal commit and exact duplicate replay.  Only one PREPARE/COMMIT/ACCEPT is
-- permitted for the request ID.
declare
  s varchar2(32);l varchar2(64);g number;t number;q number;
  status varchar2(4000);rg number;rt number;rq number;sha varchar2(64);
  command raw(32767):=hextoraw(
    '444D53430101000000000000000000010000000000000000');
begin
  select c.target_session,c.target_lineage,c.generation,gs.current_tic,gs.last_command_seq
    into s,l,g,t,q from doom_utx_control c join game_sessions gs
      on gs.session_token=c.target_session where c.singleton=1;
  doom_utx_probe.step(s,l,g,'11111111111111111111111111111111',t,q,command,null,
    status,rg,rt,rq,sha);
  if status<>'COMMITTED' or rt<>t+1 or rq<>q+1 then
    raise_application_error(-20000,'normal commit '||status);end if;
  doom_utx_probe.step(s,l,g,'11111111111111111111111111111111',t,q,command,null,
    status,rg,rt,rq,sha);
  if status<>'COMMITTED' then raise_application_error(-20000,'duplicate replay');end if;
  declare n number;begin
    select count(*) into n from doom_utx_audit
      where request_id='11111111111111111111111111111111' and audit_event='COMMIT';
    if n<>1 then raise_application_error(-20000,'duplicate executed twice');end if;
  end;
  dbms_output.put_line('unified_tx_commit_idempotency=PASS');
end;
/

-- Corrupted version/count/length and an injected persistence failure all
-- discard pending Java state and leave both relational frontiers unchanged.
declare
  s varchar2(32);l varchar2(64);g number;t number;q number;
  status varchar2(4000);rg number;rt number;rq number;sha varchar2(64);
  command raw(32767);request_id varchar2(32);
  type texts is table of varchar2(16);faults texts:=texts('BAD_MAGIC','BAD_COUNT','BAD_LENGTH','PRECOMMIT');
begin
  select c.target_session,c.target_lineage,c.generation,gs.current_tic,gs.last_command_seq
    into s,l,g,t,q from doom_utx_control c join game_sessions gs
      on gs.session_token=c.target_session where c.singleton=1;
  for i in 1..faults.count loop
    request_id:=lpad(to_char(i+1),32,to_char(i+1));
    command:=hextoraw('444D53430101000000000000'||
      lpad(to_char(q+1,'FMXXXXXXXX'),8,'0')||'0000000000000000');
    doom_utx_probe.step(s,l,g,request_id,t,q,command,faults(i),status,rg,rt,rq,sha);
    if substr(status,1,7)<>'FAILED|' then
      raise_application_error(-20000,'fault accepted '||faults(i));end if;
    declare actual_tic number;actual_seq number;begin
      select current_tic,last_command_seq into actual_tic,actual_seq
        from game_sessions where session_token=s;
      if actual_tic<>t or actual_seq<>q then
        raise_application_error(-20000,'fault advanced frontier');end if;
    end;
  end loop;
  dbms_output.put_line('unified_tx_raw_rollback_discard=PASS');
end;
/

-- A stale database frontier and wrong generation fail before prepare.
declare
  s varchar2(32);l varchar2(64);g number;t number;q number;
  status varchar2(4000);rg number;rt number;rq number;sha varchar2(64);
  command raw(32767);
begin
  select c.target_session,c.target_lineage,c.generation,gs.current_tic,gs.last_command_seq
    into s,l,g,t,q from doom_utx_control c join game_sessions gs
      on gs.session_token=c.target_session where c.singleton=1;
  command:=hextoraw('444D53430101000000000000'||
    lpad(to_char(q+1,'FMXXXXXXXX'),8,'0')||'0000000000000000');
  doom_utx_probe.step(s,l,g,'77777777777777777777777777777777',t-1,q,command,null,
    status,rg,rt,rq,sha);
  if substr(status,1,7)<>'FAILED|' then raise_application_error(-20000,'stale tic accepted');end if;
  doom_utx_probe.step(s,l,g+1,'88888888888888888888888888888888',t,q,command,null,
    status,rg,rt,rq,sha);
  if substr(status,1,7)<>'FAILED|' then raise_application_error(-20000,'generation accepted');end if;
  dbms_output.put_line('unified_tx_frontier_generation_fence=PASS');
end;
/

-- A post-commit accept failure cannot roll back SQL.  It must reconstruct from
-- the committed frontier under a new generation and reject the old generation.
declare
  s varchar2(32);l varchar2(64);g number;t number;q number;
  status varchar2(4000);rg number;rt number;rq number;sha varchar2(64);
  command raw(32767);new_generation number;reconstruct_events number;
begin
  select c.target_session,c.target_lineage,c.generation,gs.current_tic,gs.last_command_seq
    into s,l,g,t,q from doom_utx_control c join game_sessions gs
      on gs.session_token=c.target_session where c.singleton=1;
  command:=hextoraw('444D53430101000000000000'||
    lpad(to_char(q+1,'FMXXXXXXXX'),8,'0')||'0000000000000000');
  doom_utx_probe.step(s,l,g,'99999999999999999999999999999999',t,q,command,'ACCEPT',
    status,rg,rt,rq,sha);
  if status<>'COMMITTED' or rt<>t+1 or rq<>q+1 or rg<>g+1 then
    raise_application_error(-20000,'accept recovery result '||status);end if;
  select generation into new_generation from doom_utx_control where singleton=1;
  select count(*) into reconstruct_events from doom_utx_audit
    where request_id='99999999999999999999999999999999'
      and generation=new_generation and audit_event='RECONSTRUCT';
  if new_generation<>g+1 or reconstruct_events<>1 then
    raise_application_error(-20000,'missing retained-worker reconstruction');end if;
  dbms_output.put_line('unified_tx_postcommit_reconstruction=PASS');
end;
/

-- Stop and restart the Scheduler session.  The next generation must rebuild
-- from committed relational state and execute the next command exactly once.
begin doom_utx_probe.request_stop;end;
/
declare deadline timestamp with time zone:=systimestamp+interval '10' second;n number;
begin loop
  select count(*) into n from user_scheduler_running_jobs where job_name='DOOM_UTX_PROBE_JOB';
  exit when n=0;
  if systimestamp>deadline then raise_application_error(-20000,'worker stop timeout');end if;
  dbms_session.sleep(.05);
end loop;end;
/
update doom_utx_control set stop_requested=0,ready=0 where singleton=1;
commit;
begin dbms_scheduler.run_job('DOOM_UTX_PROBE_JOB',false);end;
/
declare
  old_generation number;ready_ number;generation_ number;error_ varchar2(4000);
  deadline timestamp with time zone:=systimestamp+interval '20' second;
begin
  select max(generation) into old_generation from doom_utx_audit
    where audit_event='WORKER_STOP';
  loop
    select ready,generation,last_error into ready_,generation_,error_
      from doom_utx_control where singleton=1;
    if error_ is not null then raise_application_error(-20000,error_);end if;
    exit when ready_=1 and generation_>old_generation;
    if systimestamp>deadline then raise_application_error(-20000,'worker restart timeout');end if;
    dbms_session.sleep(.05);
  end loop;
end;
/
declare
  s varchar2(32);l varchar2(64);g number;t number;q number;
  status varchar2(4000);rg number;rt number;rq number;sha varchar2(64);
  command raw(32767);
begin
  select c.target_session,c.target_lineage,c.generation,gs.current_tic,gs.last_command_seq
    into s,l,g,t,q from doom_utx_control c join game_sessions gs
      on gs.session_token=c.target_session where c.singleton=1;
  command:=hextoraw('444D53430101000000000000'||
    lpad(to_char(q+1,'FMXXXXXXXX'),8,'0')||'0000000000000000');
  doom_utx_probe.step(s,l,g,'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',t,q,command,null,
    status,rg,rt,rq,sha);
  if status<>'COMMITTED' or rt<>t+1 or rq<>q+1 then
    raise_application_error(-20000,'restart command '||status);end if;
  dbms_output.put_line('unified_tx_scheduler_restart=PASS');
end;
/

select request_status,count(*) requests from doom_utx_request
group by request_status order by request_status;
select audit_event,count(*) events from doom_utx_audit
group by audit_event order by audit_event;
select generation,ready,worker_sid,last_error from doom_utx_control;

begin doom_utx_probe.request_stop;end;
/
declare deadline timestamp with time zone:=systimestamp+interval '10' second;n number;
begin loop
  select count(*) into n from user_scheduler_running_jobs where job_name='DOOM_UTX_PROBE_JOB';
  exit when n=0;
  if systimestamp>deadline then raise_application_error(-20000,'final worker stop timeout');end if;
  dbms_session.sleep(.05);
end loop;end;
/

declare l_session varchar2(32);
begin
  select target_session into l_session from doom_utx_control where singleton=1;
  dbms_scheduler.drop_job('DOOM_UTX_PROBE_JOB',true);
  dbms_aqadm.stop_queue('DOOM_UTX_REQUEST_Q');
  dbms_aqadm.stop_queue('DOOM_UTX_RESPONSE_Q');
  dbms_aqadm.drop_queue('DOOM_UTX_REQUEST_Q');
  dbms_aqadm.drop_queue('DOOM_UTX_RESPONSE_Q');
  dbms_aqadm.drop_queue_table('DOOM_UTX_REQUEST_QT',true);
  dbms_aqadm.drop_queue_table('DOOM_UTX_RESPONSE_QT',true);
  delete from game_sessions where session_token=l_session;
  commit;
end;
/
drop package doom_utx_probe;
drop table doom_utx_audit purge;
drop table doom_utx_result purge;
drop table doom_utx_request purge;
drop table doom_utx_control purge;
