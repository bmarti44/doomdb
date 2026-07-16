whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;
  map_clob_ clob;map_blob_ blob;committed_blob_ blob;pending_blob_ blob;
  map_sha_ varchar2(64);committed_sha_ varchar2(64);pending_sha_ varchar2(64);
  result_ varchar2(4000);request_ varchar2(32);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number;actors_ number;
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
begin
  doom_api.new_game(3,session_,payload_);
  select save_lineage,current_tic,last_command_seq,rng_cursor
    into lineage_,tic_,seq_,rng_ from game_sessions where session_token=session_;
  select coalesce(max(mobj_id),0)+1,count(*) into next_mobj_,actors_
    from mobjs where session_token=session_;
  select coalesce(max(event_ordinal)+1,0) into next_event_ from game_events
    where session_token=session_ and tic=tic_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,
           sprite_prefix,sprite_frame,rotations null on null returning varchar2)
           order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_clob_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  if warning_<>0 then raise_application_error(-20000,'state map UTF-8');end if;
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  dbms_lob.createtemporary(committed_blob_,true,dbms_lob.call);
  dbms_lob.createtemporary(pending_blob_,true,dbms_lob.call);

  -- A mismatched immutable state-index mapping cannot publish retained state.
  result_:=doom_retained_world_load(session_,lineage_,1,rpad('0',64,'0'),committed_blob_);
  if substr(result_,1,4)<>'ERR|' or instr(result_,'state map SHA fence')=0 then
    raise_application_error(-20000,'state map SHA fence accepted '||result_);
  end if;
  result_:=doom_retained_world_load(session_,lineage_,1,map_sha_,committed_blob_);
  if substr(result_,1,3)<>'OK|' or instr(result_,'|'||tic_||'|'||seq_||'|'||rng_||'|'||
       next_mobj_||'|'||next_event_||'|'||actors_||'|')=0 then
    raise_application_error(-20000,'world load '||result_);
  end if;
  committed_sha_:=lower(rawtohex(dbms_crypto.hash(committed_blob_,dbms_crypto.hash_sh256)));

  -- Wrong generation/frontier requests fail before pending state is exposed.
  result_:=doom_retained_world_prepare(session_,lineage_,2,
    '11111111111111111111111111111111',tic_,seq_,rng_,next_mobj_,next_event_,pending_blob_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'world generation accepted');end if;
  result_:=doom_retained_world_prepare(session_,lineage_,1,
    '11111111111111111111111111111111',tic_+1,seq_,rng_,next_mobj_,next_event_,pending_blob_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'world frontier accepted');end if;

  request_:='22222222222222222222222222222222';
  result_:=doom_retained_world_prepare(session_,lineage_,1,request_,
    tic_,seq_,rng_,next_mobj_,next_event_,pending_blob_);
  if substr(result_,1,3)<>'OK|' or dbms_lob.compare(committed_blob_,pending_blob_)<>0 then
    raise_application_error(-20000,'world pending roundtrip '||result_);
  end if;
  pending_sha_:=lower(rawtohex(dbms_crypto.hash(pending_blob_,dbms_crypto.hash_sh256)));
  if pending_sha_<>committed_sha_ then raise_application_error(-20000,'world pending SHA');end if;
  result_:=doom_retained_world_load(session_,lineage_,1,map_sha_,pending_blob_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'pending world load accepted');end if;
  result_:=doom_retained_world_discard(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;

  -- Relational mutation after load cannot alter the retained exact NUMBER image.
  savepoint retained_loaded;
  update players set x=x+1 where session_token=session_;
  request_:='33333333333333333333333333333333';
  result_:=doom_retained_world_prepare(session_,lineage_,1,request_,
    tic_,seq_,rng_,next_mobj_,next_event_,pending_blob_);
  if substr(result_,1,3)<>'OK|' or dbms_lob.compare(committed_blob_,pending_blob_)<>0 then
    raise_application_error(-20000,'relational mutation leaked into retained image');
  end if;
  result_:=doom_retained_world_discard(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  rollback to retained_loaded;

  request_:='44444444444444444444444444444444';
  result_:=doom_retained_world_prepare(session_,lineage_,1,request_,
    tic_,seq_,rng_,next_mobj_,next_event_,pending_blob_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  result_:=doom_retained_world_accept(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  result_:=doom_retained_world_accept(session_,lineage_,1,request_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'double world accept');end if;

  dbms_output.put_line('retained_world_state_roundtrip='||actors_||'/'||actors_);
  dbms_output.put_line('retained_world_state_map_sha='||map_sha_);
  dbms_output.put_line('retained_world_state_pack='||dbms_lob.getlength(committed_blob_)||'|'||committed_sha_);
  dbms_output.put_line('retained_world_state_fences=PASS');
  rollback;
end;
/
