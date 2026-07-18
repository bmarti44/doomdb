whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  type numbers_t is table of number index by pls_integer;
  l_values numbers_t;l_session varchar2(32);l_payload blob;
  l_started timestamp with time zone;l_value number;l_active number;
  l_deadline timestamp with time zone;l_worker_p50 number;l_worker_p95 number;
  l_render_p95 number;l_ticker_p95 number;l_codec_p95 number;l_blob_p95 number;
  l_previous_engine varchar2(4000);

  function elapsed_ms(p_span interval day to second) return number is
  begin
    return round((extract(day from p_span)*86400+extract(hour from p_span)*3600+
      extract(minute from p_span)*60+extract(second from p_span))*1000,3);
  end;
  function command_json(p_seq number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||',"turn":'||
      case when mod(p_seq,31)<8 then 1 else 0 end||
      ',"forward":1,"strafe":0,"run":1,"fire":'||
      case when mod(p_seq-1,8)=0 then 1 else 0 end||
      ',"use":0,"weapon":0,"pause":0,"automap":0,'||
      '"menu":"NONE","cheat":""}]}';
  end;
  procedure cleanup is
  begin
    if l_session is not null then
      update doom_worker_control set stop_requested=1
        where target_session=l_session;commit;
      l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
      loop
        select count(*) into l_active from doom_worker_control
          where target_session=l_session;
        exit when l_active=0 or systimestamp>=l_deadline;
        dbms_session.sleep(.1);
      end loop;
      delete from game_sessions where session_token=l_session;
    end if;
    update doom_config set text_value=coalesce(l_previous_engine,text_value)
      where config_key='GAME_ENGINE';commit;
  end;
begin
  select text_value into l_previous_engine from doom_config
    where config_key='GAME_ENGINE';
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_session,l_payload);
  for i in 1..330 loop
    l_started:=systimestamp;
    doom_api.step(l_session,command_json(i),l_payload);
    if i>30 then l_values(i-30):=elapsed_ms(systimestamp-l_started);end if;
  end loop;
  for i in 2..300 loop
    l_value:=l_values(i);
    declare j pls_integer:=i-1;begin
      while j>=1 and l_values(j)>l_value loop
        l_values(j+1):=l_values(j);j:=j-1;
      end loop;
      l_values(j+1):=l_value;
    end;
  end loop;
  select round(percentile_cont(.5) within group(order by
      extract(day from(q.completed_at-q.created_at))*86400000+
      extract(hour from(q.completed_at-q.created_at))*3600000+
      extract(minute from(q.completed_at-q.created_at))*60000+
      extract(second from(q.completed_at-q.created_at))*1000),3),
    round(percentile_cont(.95) within group(order by
      extract(day from(q.completed_at-q.created_at))*86400000+
      extract(hour from(q.completed_at-q.created_at))*3600000+
      extract(minute from(q.completed_at-q.created_at))*60000+
      extract(second from(q.completed_at-q.created_at))*1000),3),
    round(percentile_cont(.95) within group(order by r.render_us)/1000,3),
    round(percentile_cont(.95) within group(order by r.actor_tic_us)/1000,3),
    round(percentile_cont(.95) within group(order by r.codec_us)/1000,3),
    round(percentile_cont(.95) within group(order by r.blob_us)/1000,3)
    into l_worker_p50,l_worker_p95,l_render_p95,l_ticker_p95,l_codec_p95,l_blob_p95
    from doom_worker_request q join doom_worker_result r
      on r.request_id=q.request_id
    where q.session_token=l_session and r.committed_tic>30;
  dbms_output.put_line('PASS MOCHADOOM-RETAINED-WORKER samples=300'||
    ' apiP50Ms='||l_values(150)||' apiP95Ms='||l_values(285)||
    ' apiP99Ms='||l_values(297)||' apiMaxMs='||l_values(300)||
    ' workerP50Ms='||l_worker_p50||' workerP95Ms='||l_worker_p95||
    ' tickerP95Ms='||l_ticker_p95||' renderP95Ms='||l_render_p95||
    ' codecP95Ms='||l_codec_p95||' blobP95Ms='||l_blob_p95||
    ' payloadBytes='||dbms_lob.getlength(l_payload));
  cleanup;
exception when others then cleanup;raise;
end;
/
