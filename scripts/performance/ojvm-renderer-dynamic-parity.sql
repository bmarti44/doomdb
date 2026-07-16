whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  a_ varchar2(32);b_ varchar2(32);sql_payload_ blob;ignored_ blob;
  snapshot_a_ blob;snapshot_b_ blob;java_payload_ blob;
  sha_a1_ varchar2(4000);sha_a2_ varchar2(4000);sha_b_ varchar2(4000);
  result_ varchar2(4000);frames_ sys.odcivarchar2list:=sys.odcivarchar2list();
  expected_ constant varchar2(64):=rpad('0',64,'0');
  command_ clob;angle_ number;tic_ number;

  procedure render_and_compare(p_session varchar2,p_snapshot in out nocopy blob,p_sql blob) is
    frame_sha varchar2(4000);comparison varchar2(4000);
  begin
    doom_renderer_snapshot_fill(p_session,p_snapshot);
    frame_sha:=doom_bsp_render_packed_session(p_session,p_snapshot,expected_,java_payload_);
    if not regexp_like(frame_sha,'^[0-9a-f]{64}$') then
      raise_application_error(-20000,'packed render '||frame_sha);
    end if;
    comparison:=doom_bsp_compare_current_payload(p_sql);
    if comparison<>'0|0|0|320|-1|200|-1' then
      raise_application_error(-20000,'packed SQL parity '||comparison);
    end if;
    frames_.extend;frames_(frames_.count):=frame_sha;
  end;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  dbms_lob.createtemporary(snapshot_a_,true);dbms_lob.createtemporary(snapshot_b_,true);
  dbms_lob.createtemporary(java_payload_,true);
  doom_api.new_game(3,a_,sql_payload_);
  render_and_compare(a_,snapshot_a_,sql_payload_);

  -- One composite public STEP changes angle, exact fractional position, actor
  -- states/positions and animation tic together. SQL remains the byte oracle;
  -- the two resulting frames are required to be distinct.
  for seq_ in 1..1 loop
    command_:=to_clob('{"v":1,"commands":[{"turn":'||
      '1'||',"forward":1,"strafe":1'||
      ',"run":1,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,'||
      '"menu":"NONE","cheat":"","seq":'||seq_||'}]}');
    doom_api.step(a_,command_,sql_payload_);
    render_and_compare(a_,snapshot_a_,sql_payload_);
  end loop;
  select count(distinct column_value) into tic_ from table(frames_);
  if tic_<>frames_.count then
    raise_application_error(-20000,'moving renderer frames not unique');
  end if;

  -- A-B-A in one database session proves every dynamic array is overwritten by
  -- its packed owner. The explicit owner fence rejects cross-game locators.
  doom_api.new_game(3,b_,ignored_);
  update players set angle=11.25 where session_token=b_ and player_id=(select current_player_id
    from game_sessions where session_token=b_);
  doom_renderer_snapshot_fill(a_,snapshot_a_);
  doom_renderer_snapshot_fill(b_,snapshot_b_);
  sha_a1_:=doom_bsp_render_packed_session(a_,snapshot_a_,expected_,java_payload_);
  sha_b_:=doom_bsp_render_packed_session(b_,snapshot_b_,expected_,java_payload_);
  sha_a2_:=doom_bsp_render_packed_session(a_,snapshot_a_,expected_,java_payload_);
  if not regexp_like(sha_a1_,'^[0-9a-f]{64}$') or
     not regexp_like(sha_b_,'^[0-9a-f]{64}$') or
     not regexp_like(sha_a2_,'^[0-9a-f]{64}$') or
     sha_a1_<>sha_a2_ or sha_a1_=sha_b_ then
    raise_application_error(-20000,'renderer A-B-A isolation');
  end if;
  result_:=doom_bsp_render_packed_session(b_,snapshot_a_,expected_,java_payload_);
  if result_ not like 'ERROR:%' or dbms_lob.getlength(java_payload_)<>0 then
    raise_application_error(-20000,'renderer session fence accepted');
  end if;
  select angle,current_tic into angle_,tic_ from players p join game_sessions s
    on s.session_token=p.session_token and s.current_player_id=p.player_id
    where s.session_token=a_;
  dbms_output.put_line('DYNAMIC_RENDERER_PARITY_OK frames='||frames_.count||
    ' angle='||angle_||' tic='||tic_||' snapshot_bytes='||dbms_lob.getlength(snapshot_a_));
  dbms_output.put_line('DYNAMIC_RENDERER_ISOLATION_OK a='||substr(sha_a1_,1,12)||
    ' b='||substr(sha_b_,1,12)||' a2='||substr(sha_a2_,1,12));
end;
/
