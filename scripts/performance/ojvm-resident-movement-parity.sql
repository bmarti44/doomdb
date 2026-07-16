whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;sql_payload clob;
  result_ varchar2(4000);request_ varchar2(32);command_pack raw(32767);delta_ raw(32767);
  x_ number;y_ number;z_ number;angle_ number;expected_x number;expected_y number;expected_z number;
  actual_x number;actual_y number;actual_z number;actual_angle binary_double;
  dx_ number;dy_ number;turn_ pls_integer;forward_ pls_integer;strafe_ pls_integer;run_ pls_integer;
  length_ pls_integer;contacts_ pls_integer:=0;
  samples_ sys.odcinumberlist:=sys.odcinumberlist();started_ timestamp with time zone;
  elapsed_ interval day to second;ms_ number;p50_ number;p95_ number;max_ number;
  function same_number(p_left number,p_right number) return boolean is same_ number;begin
    select case when dump(p_left,16)=dump(p_right,16) then 1 else 0 end into same_ from dual;
    return same_=1;
  end;
begin
  result_:=doom_sim_catalog_load;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  doom_api.new_game(3,session_,payload_);
  select g.save_lineage,p.x,p.y,p.z,p.angle into lineage_,x_,y_,z_,angle_
    from game_sessions g join players p on p.session_token=g.session_token
      and p.player_id=g.current_player_id where g.session_token=session_;
  result_:=doom_resident_sim_load_exact_player(session_,lineage_,1,0,0,x_,y_,z_,
    to_binary_double(angle_));
  if result_<>'OK' then raise_application_error(-20000,result_);end if;

  for seq_ in 1..270 loop
    turn_:=case mod(seq_,9) when 0 then 1 when 4 then -1 else 0 end;
    forward_:=1;strafe_:=case when mod(seq_,17)=0 then 1 else 0 end;
    run_:=case when mod(seq_,5)=0 then 1 else 0 end;
    angle_:=mod(angle_+turn_*5.625+360,360);
    dx_:=(forward_*cos(angle_*acos(-1)/180)+strafe_*sin(angle_*acos(-1)/180))*8*(run_+1);
    dy_:=(forward_*sin(angle_*acos(-1)/180)-strafe_*cos(angle_*acos(-1)/180))*8*(run_+1);
    sql_payload:=doom_player_move_payload(session_,dx_,dy_);
    expected_x:=json_value(sql_payload,'$.dest_x' returning number);
    expected_y:=json_value(sql_payload,'$.dest_y' returning number);
    expected_z:=json_value(sql_payload,'$.dest_z' returning number);
    contacts_:=contacts_+case when json_value(sql_payload,'$.contact_count' returning number)>0
      then 1 else 0 end;

    command_pack:=hextoraw('444d53430201000000000000'||
      lpad(to_char(seq_,'fmxxxxxxxx'),8,'0')||
      case turn_ when -1 then 'ff' when 0 then '00' else '01' end||
      case forward_ when -1 then 'ff' when 0 then '00' else '01' end||
      case strafe_ when -1 then 'ff' when 0 then '00' else '01' end||
      to_char(run_,'fm0x')||'00000000');
    request_:=lower(rawtohex(sys_guid()));
    delta_:=doom_resident_sim_prepare_movement(session_,lineage_,1,request_,command_pack);
    if rawtohex(utl_raw.substr(delta_,1,8))<>'444D534402000100' then
      raise_application_error(-20000,'movement delta rejected seq='||seq_||' '||
        doom_resident_sim_last_error);
    end if;
    actual_angle:=utl_raw.cast_to_binary_double(utl_raw.substr(delta_,25,8),utl_raw.big_endian);
    length_:=to_number(rawtohex(utl_raw.substr(delta_,33,1)),'xx');
    actual_x:=utl_raw.cast_to_number(utl_raw.substr(delta_,34,length_));
    length_:=to_number(rawtohex(utl_raw.substr(delta_,56,1)),'xx');
    actual_y:=utl_raw.cast_to_number(utl_raw.substr(delta_,57,length_));
    length_:=to_number(rawtohex(utl_raw.substr(delta_,79,1)),'xx');
    actual_z:=utl_raw.cast_to_number(utl_raw.substr(delta_,80,length_));
    if not same_number(actual_x,expected_x) or not same_number(actual_y,expected_y) or
       not same_number(actual_z,expected_z) or actual_angle<>to_binary_double(angle_) then
      raise_application_error(-20000,'resident movement mismatch seq='||seq_||
        ' expected='||expected_x||','||expected_y||','||expected_z||
        ' actual='||actual_x||','||actual_y||','||actual_z);
    end if;
    -- Pending movement cannot leak into committed state before SQL commit.
    if to_number(regexp_substr(doom_resident_sim_exact_state(session_,lineage_,1),
         '[^|]+',1,2))<>seq_-1 then
      raise_application_error(-20000,'movement prepare leaked seq='||seq_);
    end if;
    result_:=doom_resident_sim_accept(session_,lineage_,1,request_);
    if result_<>'OK' then raise_application_error(-20000,result_);end if;
    x_:=expected_x;y_:=expected_y;z_:=expected_z;
    update players set x=x_,y=y_,z=z_,angle=angle_ where session_token=session_
      and player_id=(select current_player_id from game_sessions where session_token=session_);
  end loop;
  dbms_output.put_line('resident_sim_movement_parity=270/270');
  dbms_output.put_line('resident_sim_movement_contact_samples='||contacts_);
  dbms_output.put_line('resident_sim_movement_transaction_fence=270/270');

  -- Production-shaped packed prepare+accept boundary, excluding relational DML.
  for sample_ in 1..300 loop
    turn_:=case mod(sample_,9) when 0 then 1 when 4 then -1 else 0 end;
    run_:=case when mod(sample_,5)=0 then 1 else 0 end;
    command_pack:=hextoraw('444d53430201000000000000'||
      lpad(to_char(270+sample_,'fmxxxxxxxx'),8,'0')||
      case turn_ when -1 then 'ff' when 0 then '00' else '01' end||'0100'||
      to_char(run_,'fm0x')||'00000000');
    request_:=lower(rawtohex(sys_guid()));started_:=systimestamp;
    delta_:=doom_resident_sim_prepare_movement(session_,lineage_,1,request_,command_pack);
    if rawtohex(utl_raw.substr(delta_,1,8))<>'444D534402000100' then
      raise_application_error(-20000,'movement benchmark rejected');
    end if;
    result_:=doom_resident_sim_accept(session_,lineage_,1,request_);
    if result_<>'OK' then raise_application_error(-20000,result_);end if;
    elapsed_:=systimestamp-started_;
    ms_:=extract(day from elapsed_)*86400000+extract(hour from elapsed_)*3600000+
      extract(minute from elapsed_)*60000+extract(second from elapsed_)*1000;
    samples_.extend;samples_(samples_.count):=ms_;
  end loop;
  select percentile_cont(.5) within group(order by column_value),
         percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(samples_);
  dbms_output.put_line('resident_sim_movement_prepare_accept_ms='||
    round(p50_,3)||'|'||round(p95_,3)||'|'||round(max_,3));
  rollback;
end;
/
