whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

begin
  begin dbms_scheduler.drop_job('DOOM_WORKER_RENDER_JOB',true); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_WORKER_RENDER_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_WORKER_RENDER_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_WORKER_RENDER_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_WORKER_RENDER_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_WORKER_RENDER_REQUEST_QT',true); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_WORKER_RENDER_RESPONSE_QT',true); exception when others then null; end;
  begin execute immediate 'drop package doom_worker_render_probe'; exception when others then null; end;
  begin execute immediate 'drop table doom_worker_render_control purge'; exception when others then null; end;
  begin execute immediate 'drop table doom_worker_render_result purge'; exception when others then null; end;
end;
/

create table doom_worker_render_control (
  singleton number(1) primary key check(singleton=1),stop_requested number(1) not null,
  generation number not null,ready number(1) not null,worker_sid number,
  heartbeat timestamp with time zone,error_text varchar2(4000),
  target_session varchar2(32) not null,state_sha varchar2(64) not null
);
insert into doom_worker_render_control
select 1,0,0,0,null,null,null,s.session_token,t.state_sha
from game_sessions s cross apply(
  select state_sha from tic_commands t where t.session_token=s.session_token
  order by tic desc fetch first 1 row only
) t where s.game_mode='GAME' and s.current_tic>0
order by s.current_tic desc fetch first 1 row only;

create table doom_worker_render_result (
  sample_no number primary key,request_id varchar2(32) not null unique,
  payload blob not null,payload_bytes number,latency_ms number,
  worker_fill_ms number,render_ms number,codec_ms number,blob_ms number,
  bsp_ms number,solid_ms number,portal_ms number,plane_ms number,sprite_ms number,
  presentation_ms number,snapshot_ms number,frame_sha varchar2(64)
  ,pack_ms number
) lob(payload) store as securefile(cache);

begin
  dbms_aqadm.create_queue_table('DOOM_WORKER_RENDER_REQUEST_QT','RAW');
  dbms_aqadm.create_queue_table('DOOM_WORKER_RENDER_RESPONSE_QT','RAW');
  dbms_aqadm.create_queue('DOOM_WORKER_RENDER_REQUEST_Q','DOOM_WORKER_RENDER_REQUEST_QT');
  dbms_aqadm.create_queue('DOOM_WORKER_RENDER_RESPONSE_Q','DOOM_WORKER_RENDER_RESPONSE_QT');
  dbms_aqadm.start_queue('DOOM_WORKER_RENDER_REQUEST_Q');
  dbms_aqadm.start_queue('DOOM_WORKER_RENDER_RESPONSE_Q');
end;
/

create or replace package doom_worker_render_probe authid definer as procedure run;end;
/

create or replace package body doom_worker_render_probe as
  function elapsed_ms(p_started timestamp with time zone) return number is
    d interval day to second:=systimestamp-p_started;
  begin return extract(day from d)*86400000+extract(hour from d)*3600000+
    extract(minute from d)*60000+extract(second from d)*1000;end;

  procedure run is
    deq dbms_aq.dequeue_options_t;enq dbms_aq.enqueue_options_t;
    props dbms_aq.message_properties_t;reply_props dbms_aq.message_properties_t;
    body raw(32767);message_id raw(16);reply_id raw(16);response blob;warm blob;snapshot blob;
    request_id varchar2(32);l_sample_no number;stop_ number:=0;
    started timestamp with time zone;fill_ms number;failure varchar2(4000);pack_started timestamp with time zone;l_pack_ms number;
    target_session varchar2(32);state_sha varchar2(64);l_frame_sha varchar2(4000);
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    update doom_worker_render_control set generation=generation+1,
      worker_sid=sys_context('USERENV','SID'),heartbeat=systimestamp,error_text=null
      where singleton=1;commit;
    select c.target_session,c.state_sha into target_session,state_sha
      from doom_worker_render_control c where singleton=1;
    dbms_lob.createtemporary(warm,true);dbms_lob.createtemporary(snapshot,true);
    -- Instance-wide JIT compilation is completed by the deployment warmup.
    -- This worker loop loads its session-private arrays and settles allocation.
    for iteration in 1..10 loop
      doom_renderer_json_snapshot_fill(target_session,snapshot);
      l_frame_sha:=doom_bsp_render_snapshot(snapshot,state_sha,warm);
      if l_frame_sha like 'ERROR:%' then raise_application_error(-20000,l_frame_sha);end if;
    end loop;
    dbms_lob.freetemporary(warm);
    update doom_worker_render_control set ready=1,heartbeat=systimestamp where singleton=1;
    commit;
    deq.wait:=1;deq.visibility:=dbms_aq.immediate;deq.navigation:=dbms_aq.first_message;
    enq.visibility:=dbms_aq.immediate;
    loop
      begin
        dbms_aq.dequeue('DOOM_WORKER_RENDER_REQUEST_Q',deq,props,body,message_id);
        request_id:=utl_raw.cast_to_varchar2(body);
        l_sample_no:=to_number(substr(props.correlation,1,instr(props.correlation,':')-1));
        started:=systimestamp;
        insert into doom_worker_render_result(sample_no,request_id,payload)
          values(l_sample_no,request_id,empty_blob()) returning payload into response;
        pack_started:=systimestamp;doom_renderer_json_snapshot_fill(target_session,snapshot);
        l_pack_ms:=elapsed_ms(pack_started);
        l_frame_sha:=doom_bsp_render_snapshot(snapshot,state_sha,response);
        if l_frame_sha like 'ERROR:%' then raise_application_error(-20000,l_frame_sha);end if;
        fill_ms:=elapsed_ms(started);
        update doom_worker_render_result set payload_bytes=dbms_lob.getlength(payload),
          worker_fill_ms=fill_ms,render_ms=doom_bsp_last_render_ns/1e6,
          codec_ms=doom_bsp_last_codec_ns/1e6,blob_ms=doom_bsp_last_blob_ns/1e6,
          bsp_ms=doom_bsp_last_bsp_ns/1e6,solid_ms=doom_bsp_last_solid_ns/1e6,
          portal_ms=doom_bsp_last_portal_ns/1e6,plane_ms=doom_bsp_last_plane_ns/1e6,
          sprite_ms=doom_bsp_last_sprite_ns/1e6,
          presentation_ms=doom_bsp_last_presentation_ns/1e6,
          snapshot_ms=doom_bsp_last_snapshot_ns/1e6,frame_sha=l_frame_sha,pack_ms=l_pack_ms
          where sample_no=l_sample_no;
        update doom_worker_render_control set heartbeat=systimestamp where singleton=1;
        commit;
        reply_props.correlation:=props.correlation;
        dbms_aq.enqueue('DOOM_WORKER_RENDER_RESPONSE_Q',enq,reply_props,body,reply_id);
      exception when no_messages then null;
      end;
      select stop_requested into stop_ from doom_worker_render_control where singleton=1;
      exit when stop_=1;
    end loop;
  exception when others then
    begin
      failure:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
      update doom_worker_render_control set stop_requested=1,ready=0,
        error_text=failure,
        heartbeat=systimestamp where singleton=1;commit;
    exception when others then null;end;
  end;
end;
/

begin
  dbms_scheduler.create_job(job_name=>'DOOM_WORKER_RENDER_JOB',
    job_type=>'STORED_PROCEDURE',job_action=>'DOOM_WORKER_RENDER_PROBE.RUN',
    start_date=>systimestamp,enabled=>true,auto_drop=>false);
end;
/

declare ready_ number;error_ varchar2(4000);deadline timestamp with time zone:=systimestamp+interval '3' minute;
begin loop
  select ready,error_text into ready_,error_ from doom_worker_render_control where singleton=1;
  if error_ is not null then raise_application_error(-20000,error_);end if;
  exit when ready_=1;
  if systimestamp>deadline then raise_application_error(-20000,'render worker warmup timeout');end if;
  dbms_session.sleep(.1);
end loop;end;
/

declare
  enq dbms_aq.enqueue_options_t;deq dbms_aq.dequeue_options_t;
  props dbms_aq.message_properties_t;reply_props dbms_aq.message_properties_t;
  body raw(32767);reply raw(32767);message_id raw(16);reply_id raw(16);
  request_id varchar2(32);correlation varchar2(128);started timestamp with time zone;
  d interval day to second;ms number;
begin
  enq.visibility:=dbms_aq.immediate;deq.visibility:=dbms_aq.immediate;deq.wait:=10;
  for sample in 1..300 loop
    request_id:=lower(rawtohex(sys_guid()));correlation:=sample||':'||request_id;
    body:=utl_raw.cast_to_raw(request_id);props.correlation:=correlation;started:=systimestamp;
    dbms_aq.enqueue('DOOM_WORKER_RENDER_REQUEST_Q',enq,props,body,message_id);
    deq.correlation:=correlation;deq.navigation:=dbms_aq.first_message;
    dbms_aq.dequeue('DOOM_WORKER_RENDER_RESPONSE_Q',deq,reply_props,reply,reply_id);
    d:=systimestamp-started;
    ms:=extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
    update doom_worker_render_result set latency_ms=ms where sample_no=sample;
    if utl_raw.cast_to_varchar2(reply)<>request_id then
      raise_application_error(-20000,'correlation payload mismatch');end if;
  end loop;commit;
end;
/

select count(*) samples,
  round(percentile_cont(.5) within group(order by latency_ms),3) p50_ms,
  round(percentile_cont(.95) within group(order by latency_ms),3) p95_ms,
  round(max(latency_ms),3) max_ms,
  round(percentile_cont(.95) within group(order by worker_fill_ms),3) fill_p95_ms,
  round(percentile_cont(.95) within group(order by render_ms),3) render_p95_ms,
  round(percentile_cont(.95) within group(order by codec_ms),3) codec_p95_ms,
  round(percentile_cont(.95) within group(order by blob_ms),3) blob_p95_ms,
  round(percentile_cont(.95) within group(order by bsp_ms),3) bsp_p95_ms,
  round(percentile_cont(.95) within group(order by solid_ms),3) solid_p95_ms,
  round(percentile_cont(.95) within group(order by portal_ms),3) portal_p95_ms,
  round(percentile_cont(.95) within group(order by plane_ms),3) plane_p95_ms,
  round(percentile_cont(.95) within group(order by sprite_ms),3) sprite_p95_ms,
  round(percentile_cont(.95) within group(order by presentation_ms),3) present_p95_ms,
  round(percentile_cont(.95) within group(order by snapshot_ms),3) snapshot_p95_ms,
  round(percentile_cont(.95) within group(order by pack_ms),3) pack_p95_ms,
  count(distinct frame_sha) frame_shas,
  min(payload_bytes) min_bytes,max(payload_bytes) max_bytes
from doom_worker_render_result;

select generation,worker_sid,ready,error_text from doom_worker_render_control;

update doom_worker_render_control set stop_requested=1 where singleton=1;
commit;
begin
  for attempt in 1..100 loop
    declare n number;begin select count(*) into n from user_scheduler_running_jobs
      where job_name='DOOM_WORKER_RENDER_JOB';if n=0 then return;end if;end;
    dbms_session.sleep(.05);
  end loop;
  raise_application_error(-20000,'render worker did not stop');
end;
/

begin
  dbms_scheduler.drop_job('DOOM_WORKER_RENDER_JOB',true);
  dbms_aqadm.stop_queue('DOOM_WORKER_RENDER_REQUEST_Q');
  dbms_aqadm.stop_queue('DOOM_WORKER_RENDER_RESPONSE_Q');
  dbms_aqadm.drop_queue('DOOM_WORKER_RENDER_REQUEST_Q');
  dbms_aqadm.drop_queue('DOOM_WORKER_RENDER_RESPONSE_Q');
  dbms_aqadm.drop_queue_table('DOOM_WORKER_RENDER_REQUEST_QT',true);
  dbms_aqadm.drop_queue_table('DOOM_WORKER_RENDER_RESPONSE_QT',true);
end;
/
drop package doom_worker_render_probe;
drop table doom_worker_render_control purge;
drop table doom_worker_render_result purge;
