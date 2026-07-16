whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  first_ blob;second_ blob;map_sha_ varchar2(64);result_ varchar2(4000);
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
begin
  doom_api.new_game(3,session_,payload_);
  select save_lineage into lineage_ from game_sessions where session_token=session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_clob_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'world owner load '||result_);end if;
  result_:=doom_unified_world_sql_parity(session_,lineage_,1);
  if result_<>'OK|280' then raise_application_error(-20000,'world owner SQL parity '||result_);end if;
  dbms_lob.createtemporary(first_,true,dbms_lob.call);dbms_lob.createtemporary(second_,true,dbms_lob.call);
  result_:=doom_unified_world_checkpoint(session_,lineage_,1,first_);
  if substr(result_,1,7)<>'OK|280|' then raise_application_error(-20000,'world checkpoint '||result_);end if;
  result_:=doom_unified_world_spawn_remove(session_,lineage_,1);
  if substr(result_,1,10)<>'OK|280|281' then raise_application_error(-20000,'world append/remove '||result_);end if;
  savepoint relational_drift;
  update mobjs set x=x+1 where session_token=session_ and mobj_id=(select min(mobj_id)
    from mobjs where session_token=session_);
  result_:=doom_unified_world_sql_parity(session_,lineage_,1);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'world drift not fenced');end if;
  result_:=doom_unified_world_restore(session_,lineage_,1,first_);
  if substr(result_,1,7)<>'OK|280|' then raise_application_error(-20000,'world restore '||result_);end if;
  result_:=doom_unified_world_checkpoint(session_,lineage_,1,second_);
  if substr(result_,1,7)<>'OK|280|' or dbms_lob.compare(first_,second_)<>0 then
    raise_application_error(-20000,'world canonical roundtrip '||result_);end if;
  rollback to relational_drift;
  result_:=doom_unified_world_sql_parity(session_,lineage_,1);
  if result_<>'OK|280' then raise_application_error(-20000,'world restore SQL parity '||result_);end if;
  dbms_output.put_line('UNIFIED_WORLD_OWNER_PARITY_OK rows=280 pack='||dbms_lob.getlength(first_));
  dbms_output.put_line('unified_world_spawn_remove_roundtrip=280|281|280');
  rollback;
end;
/
