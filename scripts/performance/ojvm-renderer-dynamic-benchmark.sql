whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);oracle_payload_ blob;snapshot_ blob;packed_payload_ blob;jdbc_payload_ blob;
  packed_sha_ varchar2(4000);jdbc_sha_ varchar2(4000);
  frame_shas_ sys.odcivarchar2list:=sys.odcivarchar2list();
  snapshot_samples_ sys.odcinumberlist:=sys.odcinumberlist();
  composite_samples_ sys.odcinumberlist:=sys.odcinumberlist();
  started_ timestamp with time zone;elapsed_ interval day to second;ms_ number;
  snapshot_p50_ number;snapshot_p95_ number;snapshot_max_ number;
  composite_p50_ number;composite_p95_ number;composite_max_ number;
  distinct_frames_ number;
  zero_sha_ constant varchar2(64):=rpad('0',64,'0');

  function milliseconds(p_elapsed interval day to second) return number is
  begin
    return extract(day from p_elapsed)*86400000+extract(hour from p_elapsed)*3600000+
      extract(minute from p_elapsed)*60000+extract(second from p_elapsed)*1000;
  end;

  procedure set_angle(p_index pls_integer) is
  begin
    update players set angle=mod(p_index,64)*5.625
      where session_token=session_ and player_id=(select current_player_id
        from game_sessions where session_token=session_);
  end;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,session_,oracle_payload_);
  dbms_lob.createtemporary(snapshot_,true);dbms_lob.createtemporary(packed_payload_,true);
  dbms_lob.createtemporary(jdbc_payload_,true);

  -- The retained binary feed and the legacy JDBC reader must produce the same
  -- exact frame at every supported 5.625-degree camera angle.
  for angle_index_ in 0..63 loop
    set_angle(angle_index_);
    doom_renderer_snapshot_fill(session_,snapshot_);
    packed_sha_:=doom_bsp_render_packed_session(
      session_,snapshot_,zero_sha_,packed_payload_);
    jdbc_sha_:=doom_bsp_render_session(session_,zero_sha_,jdbc_payload_);
    if not regexp_like(packed_sha_,'^[0-9a-f]{64}$') or packed_sha_<>jdbc_sha_ then
      raise_application_error(-20000,'64-angle mismatch angle='||angle_index_||
        ' packed='||packed_sha_||' jdbc='||jdbc_sha_);
    end if;
    frame_shas_.extend;frame_shas_(frame_shas_.count):=packed_sha_;
  end loop;
  select count(distinct column_value) into distinct_frames_ from table(frame_shas_);
  if distinct_frames_<>64 then
    raise_application_error(-20000,'64-angle distinct frames='||distinct_frames_);
  end if;

  -- Vary angles during warmup and every measured sample. Timings exclude only
  -- the row update used to select the next unique live camera state.
  for warmup_ in 1..16 loop
    set_angle(warmup_*17);doom_renderer_snapshot_fill(session_,snapshot_);
    packed_sha_:=doom_bsp_render_packed_session(session_,snapshot_,zero_sha_,packed_payload_);
    if not regexp_like(packed_sha_,'^[0-9a-f]{64}$') then
      raise_application_error(-20000,'dynamic renderer warmup '||packed_sha_);
    end if;
  end loop;
  for sample_ in 1..300 loop
    set_angle(sample_*17);
    started_:=systimestamp;doom_renderer_snapshot_fill(session_,snapshot_);
    elapsed_:=systimestamp-started_;snapshot_samples_.extend;
    snapshot_samples_(snapshot_samples_.count):=milliseconds(elapsed_);
    started_:=systimestamp;packed_sha_:=doom_bsp_render_packed_session(
      session_,snapshot_,zero_sha_,packed_payload_);
    elapsed_:=systimestamp-started_;composite_samples_.extend;
    composite_samples_(composite_samples_.count):=milliseconds(elapsed_);
    if not regexp_like(packed_sha_,'^[0-9a-f]{64}$') then
      raise_application_error(-20000,'dynamic renderer sample='||sample_||' '||packed_sha_);
    end if;
  end loop;
  select percentile_cont(.5) within group(order by column_value),
         percentile_cont(.95) within group(order by column_value),max(column_value)
    into snapshot_p50_,snapshot_p95_,snapshot_max_ from table(snapshot_samples_);
  select percentile_cont(.5) within group(order by column_value),
         percentile_cont(.95) within group(order by column_value),max(column_value)
    into composite_p50_,composite_p95_,composite_max_ from table(composite_samples_);
  dbms_output.put_line('DYNAMIC_RENDERER_64_ANGLE_OK angles=64 distinct_frames='||
    distinct_frames_||' snapshot_bytes='||dbms_lob.getlength(snapshot_));
  dbms_output.put_line('drs2_snapshot_ms='||round(snapshot_p50_,3)||'|'||
    round(snapshot_p95_,3)||'|'||round(snapshot_max_,3));
  dbms_output.put_line('snapshot_render_codec_blob_ms='||round(composite_p50_,3)||'|'||
    round(composite_p95_,3)||'|'||round(composite_max_,3));
  rollback;
end;
/
