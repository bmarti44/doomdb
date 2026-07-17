whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;map_text_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);request_ varchar2(32);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;sql_pack_ raw(32767);
  java_pack_ raw(32767);sql_delta_ raw(32767);java_delta_ raw(32767);
  command_ raw(24):=hextoraw('444d53430201000000000000000000010001000000000000');
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  started_ timestamp with time zone;span_ interval day to second;decision_ms_ number;decision_ number;
  projectiles_ready_ number;
  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;
begin
  doom_api.new_game(3,session_,initial_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_text_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_text_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
  assert_(result_ like 'OK|%','owner load '||result_);
  projectiles_ready_:=doom_unified_owner_projectiles_ready(session_,lineage_,1);
  doom_retained_world_pack.build(session_,tic_+1,sql_pack_);

  request_:=lower(rawtohex(sys_guid()));
  java_delta_:=doom_unified_command_pre_world(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
  assert_(doom_unified_pre_world_requires_advance(session_,lineage_,1,request_)=0,
    'fixture unexpectedly requires full world');
  started_:=systimestamp;
  for i in 1..1000 loop decision_:=doom_unified_pre_world_requires_advance(
    session_,lineage_,1,request_);end loop;
  span_:=systimestamp-started_;decision_ms_:=(extract(day from span_)*86400+
    extract(hour from span_)*3600+extract(minute from span_)*60+extract(second from span_))*1000/1000;
  assert_(decision_=0,'repeated retained world decision');
  sql_delta_:=doom_unified_command_post_world_passive(session_,lineage_,1,request_,null,sql_pack_,0);
  assert_(rawtohex(utl_raw.substr(sql_delta_,1,6))='44554F500100','SQL passive delta');
  result_:=doom_unified_actor_discard(session_,lineage_,1,request_);
  assert_(result_='OK','SQL passive discard '||result_);

  request_:=lower(rawtohex(sys_guid()));
  java_delta_:=doom_unified_command_pre_world(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
  java_delta_:=doom_unified_command_post_world_retained(session_,lineage_,1,request_,null,0);
  java_pack_:=doom_unified_pending_world_pack(session_,lineage_,1,request_);
  assert_(utl_raw.compare(sql_pack_,java_pack_)=0,
    'SQL/retained passive pack mismatch sql='||rawtohex(sql_pack_)||' java='||rawtohex(java_pack_));
  assert_(utl_raw.compare(sql_delta_,java_delta_)=0,'SQL/retained unified delta mismatch');
  result_:=doom_unified_actor_discard(session_,lineage_,1,request_);
  assert_(result_='OK','retained passive discard '||result_);
  dbms_output.put_line('OJVM_RETAINED_PASSIVE_WORLD_PARITY_OK bytes='||utl_raw.length(java_pack_)||
    ' rows='||to_number(rawtohex(utl_raw.substr(java_pack_,7,2)),'XXXX')||
    ' draws='||to_number(rawtohex(utl_raw.substr(java_pack_,11,2)),'XXXX')||
    ' decision_ms='||round(decision_ms_,6)||' projectiles_ready='||projectiles_ready_);
  rollback;
end;
/

exit
