whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);request_ varchar2(32);command_ raw(24);delta_ raw(32767);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number:=0;
  x_ number;y_ number;z_ number;angle_ number;expected_x_ number;expected_y_ number;expected_z_ number;
  actual_x_ number;actual_y_ number;actual_z_ number;turn_ pls_integer;forward_ pls_integer;
  strafe_ pls_integer;run_ pls_integer;angle_index_ pls_integer;len_ pls_integer;nested_len_ pls_integer;
  move_ clob;before_ clob;after_ clob;restart_ blob;before_restart_ blob;after_restart_ blob;
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  function int_(p raw,o pls_integer) return binary_integer is
  begin return utl_raw.cast_to_binary_integer(utl_raw.substr(p,o,4),utl_raw.big_endian);end;
  function num_(p raw,o pls_integer) return number is n pls_integer;
  begin n:=to_number(rawtohex(utl_raw.substr(p,o,1)),'xx');
    if n<1 or n>22 then raise_application_error(-20000,'DCTC NUMBER length='||n);end if;
    return utl_raw.cast_to_number(utl_raw.substr(p,o+1,n));end;
  function same_number(a number,b number) return boolean is same_ number;begin
    select case when dump(a,16)=dump(b,16) then 1 else 0 end into same_ from dual;return same_=1;end;
  procedure eq(a number,e number,m varchar2) is begin
    if (a is null and e is not null) or (a is not null and e is null) or a<>e then
      raise_application_error(-20000,m||' actual='||a||' expected='||e);end if;end;
  procedure load_owner is begin
    select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
      from game_sessions where session_token=session_;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
    result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
    if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'command TIC load '||result_);end if;
  end;
begin
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));

  doom_api.new_game(3,session_,payload_);load_owner;
  select x,y,z,angle into x_,y_,z_,angle_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=session_;

  -- DMSC/v2 rejects unsupported action/reserved bytes without creating pending state.
  command_:=hextoraw('444d53430201000000000000000000010001000001000000');
  delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,lower(rawtohex(sys_guid())),
    tic_,seq_,rng_,next_mobj_,0,command_);
  if rawtohex(utl_raw.substr(delta_,1,6))<>'44554F500101' then
    raise_application_error(-20000,'unsupported command was not rejected');end if;

  for command_seq_ in 1..270 loop
    turn_:=case mod(command_seq_,9) when 0 then 1 when 4 then -1 else 0 end;
    forward_:=1;strafe_:=case when mod(command_seq_,17)=0 then 1 else 0 end;
    run_:=case when mod(command_seq_,5)=0 then 1 else 0 end;
    angle_index_:=mod(round(angle_/5.625)+turn_+64,64);angle_:=angle_index_*5.625;
    move_:=doom_player_move_payload(session_,
      (forward_*cos(angle_*acos(-1)/180)+strafe_*sin(angle_*acos(-1)/180))*8*(run_+1),
      (forward_*sin(angle_*acos(-1)/180)-strafe_*cos(angle_*acos(-1)/180))*8*(run_+1));
    expected_x_:=json_value(move_,'$.dest_x' returning number);
    expected_y_:=json_value(move_,'$.dest_y' returning number);
    expected_z_:=json_value(move_,'$.dest_z' returning number);
    command_:=hextoraw('444d53430201000000000000'||lpad(to_char(command_seq_,'fmxxxxxxxx'),8,'0')||
      case turn_ when -1 then 'ff' when 0 then '00' else '01' end||
      case forward_ when -1 then 'ff' when 0 then '00' else '01' end||
      case strafe_ when -1 then 'ff' when 0 then '00' else '01' end||to_char(run_,'fm0x')||'00000000');
    select json_arrayagg(json_array(mobj_id,state_id,state_tics,x,y,z,health,flags,target_mobj_id,
      sector_id,move_direction,awake,attack_cooldown,monster_health_seen,death_processed null on null
      returning varchar2) order by mobj_id returning clob) into before_ from mobjs where session_token=session_;
    request_:=lower(rawtohex(sys_guid()));
    delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
    if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000500' or
       rawtohex(utl_raw.substr(delta_,13,8))<>'4443544301000018' or
       int_(delta_,9)<>utl_raw.length(delta_)-12 then
      raise_application_error(-20000,'command TIC envelope seq='||command_seq_||' '||doom_unified_actor_last_error);end if;
    eq(int_(delta_,25),command_seq_,'DCTC command seq');eq(int_(delta_,33),tic_+1,'DCTC tic');
    eq(int_(delta_,37),angle_index_,'DCTC angle index');
    actual_x_:=num_(delta_,41);actual_y_:=num_(delta_,64);actual_z_:=num_(delta_,87);
    if not same_number(actual_x_,expected_x_) or not same_number(actual_y_,expected_y_) or
       not same_number(actual_z_,expected_z_) then raise_application_error(-20000,'DCTC movement seq='||command_seq_);end if;
    nested_len_:=int_(delta_,114);eq(nested_len_,utl_raw.length(delta_)-117,'DCTC nested exact length');
    if rawtohex(utl_raw.substr(delta_,118,6))<>'445449430100' then
      raise_application_error(-20000,'DCTC nested DTIC seq='||command_seq_);end if;
    select json_arrayagg(json_array(mobj_id,state_id,state_tics,x,y,z,health,flags,target_mobj_id,
      sector_id,move_direction,awake,attack_cooldown,monster_health_seen,death_processed null on null
      returning varchar2) order by mobj_id returning clob) into after_ from mobjs where session_token=session_;
    if dbms_lob.compare(before_,after_)<>0 then raise_application_error(-20000,'command prepare leaked world seq='||command_seq_);end if;
    select x,y,z into actual_x_,actual_y_,actual_z_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=session_;
    if not same_number(actual_x_,x_) or not same_number(actual_y_,y_) or not same_number(actual_z_,z_) then
      raise_application_error(-20000,'command prepare leaked player seq='||command_seq_);end if;
    if command_seq_=1 then
      dbms_lob.createtemporary(before_restart_,true,dbms_lob.call);dbms_lob.createtemporary(after_restart_,true,dbms_lob.call);
      result_:=doom_unified_actor_discard(session_,lineage_,1,request_);if result_<>'OK' then raise_application_error(-20000,result_);end if;
      result_:=doom_unified_world_checkpoint(session_,lineage_,1,before_restart_);
      request_:=lower(rawtohex(sys_guid()));delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
      result_:=doom_unified_actor_discard(session_,lineage_,1,request_);if result_<>'OK' then raise_application_error(-20000,result_);end if;
      result_:=doom_unified_world_checkpoint(session_,lineage_,1,after_restart_);
      if dbms_lob.compare(before_restart_,after_restart_)<>0 then raise_application_error(-20000,'command discard owner drift');end if;
      request_:=lower(rawtohex(sys_guid()));delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
    end if;
    update players set x=expected_x_,y=expected_y_,z=expected_z_,angle=angle_
      where session_token=session_ and player_id=(select current_player_id from game_sessions where session_token=session_);
    doom_monsters.advance(session_,tic_+1);
    update game_sessions set current_tic=tic_+1,last_command_seq=command_seq_ where session_token=session_;
    result_:=doom_unified_actor_accept(session_,lineage_,1,request_);if result_<>'OK' then raise_application_error(-20000,result_);end if;
    result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
    if result_ not like 'OK|%' then raise_application_error(-20000,'command owner parity seq='||command_seq_||' '||result_);end if;
    x_:=expected_x_;y_:=expected_y_;z_:=expected_z_;tic_:=tic_+1;seq_:=command_seq_;
    select rng_cursor into rng_ from game_sessions where session_token=session_;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
  end loop;
  dbms_output.put_line('UNIFIED_COMMAND_TIC_PARITY_OK commands=270 player=270 world=270 prepare_invisible=270 frontier='||tic_||'|'||seq_);
  dbms_lob.createtemporary(restart_,true,dbms_lob.call);result_:=doom_unified_world_checkpoint(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'command restart checkpoint '||result_);end if;
  result_:=doom_unified_world_restore(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'command restart restore '||result_);end if;
  result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|%' then raise_application_error(-20000,'command restart parity '||result_);end if;
  dbms_output.put_line('unified_command_tic_restart=PASS');

  doom_api.new_game(3,session_,payload_);load_owner;
  result_:=doom_unified_command_tic_benchmark(session_,lineage_,1,300,0);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'command cold benchmark '||result_);end if;
  dbms_output.put_line('unified_command_tic_cold_ns='||result_);
  doom_api.new_game(3,session_,payload_);load_owner;
  result_:=doom_unified_command_tic_benchmark(session_,lineage_,1,300,20);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'command warm benchmark '||result_);end if;
  dbms_output.put_line('unified_command_tic_warm_ns='||result_);
  rollback;
end;
/
