whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

begin
  begin dbms_scheduler.drop_job('DOOM_WORKER_PROBE_JOB',true); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_WORKER_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_WORKER_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_WORKER_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_WORKER_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_WORKER_REQUEST_QT',true); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_WORKER_RESPONSE_QT',true); exception when others then null; end;
  begin execute immediate 'drop package doom_worker_probe'; exception when others then null; end;
  begin execute immediate 'drop table doom_worker_probe_control purge'; exception when others then null; end;
  begin execute immediate 'drop table doom_worker_probe_sample purge'; exception when others then null; end;
end;
/

create table doom_worker_probe_control (
  singleton number(1) primary key check(singleton=1),
  stop_requested number(1) not null check(stop_requested in(0,1)),
  generation number not null,
  worker_sid number,
  heartbeat timestamp with time zone
);

insert into doom_worker_probe_control values(1,0,0,null,null);

create table doom_worker_probe_sample (
  sample_no number primary key,
  request_id varchar2(32) not null unique,
  latency_ms number not null,
  response_payload varchar2(64) not null
);

begin
  dbms_aqadm.create_queue_table(
    queue_table=>'DOOM_WORKER_REQUEST_QT',queue_payload_type=>'RAW');
  dbms_aqadm.create_queue_table(
    queue_table=>'DOOM_WORKER_RESPONSE_QT',queue_payload_type=>'RAW');
  dbms_aqadm.create_queue(queue_name=>'DOOM_WORKER_REQUEST_Q',
    queue_table=>'DOOM_WORKER_REQUEST_QT');
  dbms_aqadm.create_queue(queue_name=>'DOOM_WORKER_RESPONSE_Q',
    queue_table=>'DOOM_WORKER_RESPONSE_QT');
  dbms_aqadm.start_queue('DOOM_WORKER_REQUEST_Q');
  dbms_aqadm.start_queue('DOOM_WORKER_RESPONSE_Q');
end;
/

create or replace package doom_worker_probe authid definer as
  procedure run;
end doom_worker_probe;
/

create or replace package body doom_worker_probe as
  procedure run is
    l_dequeue dbms_aq.dequeue_options_t;
    l_enqueue dbms_aq.enqueue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_response_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);l_response_id raw(16);
    l_stop number:=0;
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    update doom_worker_probe_control set generation=generation+1,
      worker_sid=sys_context('USERENV','SID'),heartbeat=systimestamp
      where singleton=1;
    commit;
    l_dequeue.wait:=1;l_dequeue.visibility:=dbms_aq.immediate;
    l_dequeue.navigation:=dbms_aq.first_message;
    l_enqueue.visibility:=dbms_aq.immediate;
    loop
      begin
        dbms_aq.dequeue(queue_name=>'DOOM_WORKER_REQUEST_Q',
          dequeue_options=>l_dequeue,message_properties=>l_properties,
          payload=>l_payload,msgid=>l_message_id);
        l_response_properties.correlation:=l_properties.correlation;
        dbms_aq.enqueue(queue_name=>'DOOM_WORKER_RESPONSE_Q',
          enqueue_options=>l_enqueue,message_properties=>l_response_properties,
          payload=>l_payload,msgid=>l_response_id);
        update doom_worker_probe_control set heartbeat=systimestamp where singleton=1;
        commit;
      exception when no_messages then null;
      end;
      select stop_requested into l_stop from doom_worker_probe_control where singleton=1;
      exit when l_stop=1;
    end loop;
  exception when others then
    update doom_worker_probe_control set stop_requested=1,heartbeat=systimestamp
      where singleton=1;
    commit;
  end;
end doom_worker_probe;
/

begin
  dbms_scheduler.create_job(job_name=>'DOOM_WORKER_PROBE_JOB',
    job_type=>'STORED_PROCEDURE',job_action=>'DOOM_WORKER_PROBE.RUN',
    start_date=>systimestamp,enabled=>true,auto_drop=>false);
end;
/

declare
  l_generation number;l_deadline timestamp with time zone:=systimestamp+interval '10' second;
begin
  loop
    select generation into l_generation from doom_worker_probe_control where singleton=1;
    exit when l_generation>0;
    if systimestamp>l_deadline then raise_application_error(-20000,'worker did not start');end if;
    dbms_session.sleep(.05);
  end loop;
end;
/

declare
  l_enqueue dbms_aq.enqueue_options_t;l_dequeue dbms_aq.dequeue_options_t;
  l_properties dbms_aq.message_properties_t;l_response_properties dbms_aq.message_properties_t;
  l_payload raw(32767);l_response raw(32767);l_message_id raw(16);l_response_id raw(16);
  l_request varchar2(32);l_started timestamp with time zone;l_elapsed interval day to second;
  l_ms number;
begin
  l_enqueue.visibility:=dbms_aq.immediate;
  l_dequeue.visibility:=dbms_aq.immediate;l_dequeue.wait:=5;
  for sample in 1..300 loop
    l_request:=lower(rawtohex(sys_guid()));l_payload:=utl_raw.cast_to_raw(l_request);
    l_properties.correlation:=l_request;l_started:=systimestamp;
    dbms_aq.enqueue(queue_name=>'DOOM_WORKER_REQUEST_Q',enqueue_options=>l_enqueue,
      message_properties=>l_properties,payload=>l_payload,msgid=>l_message_id);
    l_dequeue.correlation:=l_request;l_dequeue.navigation:=dbms_aq.first_message;
    dbms_aq.dequeue(queue_name=>'DOOM_WORKER_RESPONSE_Q',dequeue_options=>l_dequeue,
      message_properties=>l_response_properties,payload=>l_response,msgid=>l_response_id);
    l_elapsed:=systimestamp-l_started;
    l_ms:=extract(day from l_elapsed)*86400000+extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+extract(second from l_elapsed)*1000;
    insert into doom_worker_probe_sample values(sample,l_request,l_ms,
      utl_raw.cast_to_varchar2(l_response));
  end loop;
  commit;
end;
/

select count(*) samples,
  round(percentile_cont(.5) within group(order by latency_ms),3) p50_ms,
  round(percentile_cont(.95) within group(order by latency_ms),3) p95_ms,
  round(max(latency_ms),3) max_ms,
  sum(case when request_id=response_payload then 0 else 1 end) mismatches
from doom_worker_probe_sample;

select generation,worker_sid,heartbeat from doom_worker_probe_control;

update doom_worker_probe_control set stop_requested=1 where singleton=1;
commit;

begin
  for attempt in 1..100 loop
    declare l_count number;begin
      select count(*) into l_count from user_scheduler_running_jobs
        where job_name='DOOM_WORKER_PROBE_JOB';
      if l_count=0 then return;end if;
    end;
    dbms_session.sleep(.05);
  end loop;
  raise_application_error(-20000,'worker did not stop');
end;
/

begin
  dbms_scheduler.drop_job('DOOM_WORKER_PROBE_JOB',true);
  dbms_aqadm.stop_queue('DOOM_WORKER_REQUEST_Q');
  dbms_aqadm.stop_queue('DOOM_WORKER_RESPONSE_Q');
  dbms_aqadm.drop_queue('DOOM_WORKER_REQUEST_Q');
  dbms_aqadm.drop_queue('DOOM_WORKER_RESPONSE_Q');
  dbms_aqadm.drop_queue_table('DOOM_WORKER_REQUEST_QT',true);
  dbms_aqadm.drop_queue_table('DOOM_WORKER_RESPONSE_QT',true);
end;
/

drop package doom_worker_probe;
drop table doom_worker_probe_control purge;
drop table doom_worker_probe_sample purge;
