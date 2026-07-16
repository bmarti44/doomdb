whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);map_sha_ varchar2(64);bad_map_sha_ varchar2(64);
  request_ varchar2(32);
  result_ varchar2(4000);old_result_ varchar2(4000);owner_status_ varchar2(4000);
  renderer_status_ varchar2(4000);direct_sha_ varchar2(4000);oracle_sha_ varchar2(64);
  initial_payload_ blob;snapshot_ blob;checkpoint_ blob;frame_ blob;oracle_frame_ blob;
  map_clob_ clob;map_blob_ blob;delta_ raw(32767);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number:=0;
  committed_tic_ number;committed_seq_ number;version_ number;count_ number;delta_sha_ varchar2(64);
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  zero_sha_ constant varchar2(64):=rpad('0',64,'0');
  procedure frontiers is
  begin
    select current_tic,last_command_seq,rng_cursor into tic_,seq_,rng_
      from game_sessions where session_token=session_;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
    next_event_:=0;
  end;
  procedure require_ok(p_value varchar2,p_label varchar2) is
  begin if p_value is null or p_value not like 'OK%' then
    raise_application_error(-20000,p_label||' '||substr(p_value,1,3000));end if;end;
  procedure prepare_render(p_generation number) is
  begin
    frontiers;request_:=lower(rawtohex(sys_guid()));
    delta_:=doom_unified_actor_prepare(session_,lineage_,p_generation,request_,'TIC',
      tic_,seq_,rng_,next_mobj_,next_event_);
    direct_sha_:=doom_unified_render_pending(session_,lineage_,p_generation,request_,zero_sha_,frame_);
    if not regexp_like(direct_sha_,'^[0-9a-f]{64}$') then
      raise_application_error(-20000,'recovery direct render '||substr(direct_sha_,1,3000));end if;
  end;
  procedure cleanup is
  begin if session_ is not null then delete from game_sessions where session_token=session_;end if;commit;end;
  procedure apply_accept(p_generation number) is
  begin
    doom_unified_delta_apply.apply_tic(session_,lineage_,tic_,seq_,delta_,committed_tic_,
      committed_seq_,version_,count_,delta_sha_);
    commit;
    result_:=doom_unified_actor_accept(session_,lineage_,p_generation,request_);
    if result_ is null or result_ not like 'OK%' then
      dbms_lob.trim(snapshot_,0);doom_renderer_snapshot_fill(session_,snapshot_);
      old_result_:=doom_unified_recover_sql_renderer(session_,lineage_,p_generation+100,
        map_sha_,snapshot_);require_ok(old_result_,'post-commit accept-failure reconstruction');
      raise_application_error(-20000,'recovery accept failed after durable commit; reconstruction verified '||
        substr(result_,1,2000));
    end if;
    result_:=doom_unified_owner_sql_parity(session_,lineage_,p_generation);
    require_ok(result_,'recovery state continuation');
  end;
  procedure oracle_parity is
  begin
    dbms_lob.trim(snapshot_,0);doom_renderer_snapshot_fill(session_,snapshot_);
    oracle_sha_:=doom_bsp_render_packed_session(session_,snapshot_,zero_sha_,oracle_frame_);
    if oracle_sha_<>direct_sha_ then raise_application_error(-20000,
      'recovery frame parity direct='||direct_sha_||' oracle='||oracle_sha_);end if;
  end;
begin
  doom_api.new_game(3,session_,initial_payload_);
  select save_lineage into lineage_ from game_sessions where session_token=session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  bad_map_sha_:=case when map_sha_=zero_sha_ then rpad('f',64,'f') else zero_sha_ end;
  dbms_lob.createtemporary(snapshot_,true);dbms_lob.createtemporary(checkpoint_,true);
  dbms_lob.createtemporary(frame_,true);dbms_lob.createtemporary(oracle_frame_,true);
  doom_renderer_snapshot_fill(session_,snapshot_);
  result_:=doom_unified_recover_sql_renderer(session_,lineage_,1,map_sha_,snapshot_);
  require_ok(result_,'initial recovery');

  -- The durable apply succeeds, but process failure is injected before either owner accepts.
  prepare_render(1);
  doom_unified_delta_apply.apply_tic(session_,lineage_,tic_,seq_,delta_,committed_tic_,
    committed_seq_,version_,count_,delta_sha_);
  commit;
  dbms_lob.trim(snapshot_,0);doom_renderer_snapshot_fill(session_,snapshot_);
  result_:=doom_unified_recover_sql_renderer(session_,lineage_,2,bad_map_sha_,snapshot_);
  if result_ not like 'ERR|%' then raise_application_error(-20000,'bad recovery accepted '||result_);end if;
  old_result_:=doom_unified_actor_accept(session_,lineage_,1,request_);
  if old_result_ not like 'ERR|%' or
     doom_retained_render_recovery_status(session_,1) not like 'ERR|%' then
    raise_application_error(-20000,'failed recovery retained stale owner');end if;
  result_:=doom_unified_recover_sql_renderer(session_,lineage_,2,map_sha_,snapshot_);
  require_ok(result_,'post-commit SQL recovery');
  old_result_:=doom_unified_actor_accept(session_,lineage_,1,request_);
  if old_result_ not like 'ERR|%' then raise_application_error(-20000,'old request accepted '||old_result_);end if;
  owner_status_:=doom_unified_actor_recovery_status(session_,lineage_,2);
  renderer_status_:=doom_retained_render_recovery_status(session_,2);
  if owner_status_<>'OK|'||committed_tic_||'|'||committed_seq_||'|2|'||map_sha_ or
     renderer_status_<>'OK|'||committed_tic_||'|'||committed_seq_||'|2' then
    raise_application_error(-20000,'SQL recovery frontier owner='||owner_status_||
      ' renderer='||renderer_status_);end if;

  -- Exact next-frame/state continuation from reconstructed SQL state.
  prepare_render(2);apply_accept(2);oracle_parity;
  result_:=doom_unified_world_checkpoint(session_,lineage_,2,checkpoint_);
  require_ok(result_,'recovery checkpoint');
  dbms_lob.trim(snapshot_,0);doom_renderer_snapshot_fill(session_,snapshot_);
  result_:=doom_unified_recover_checkpoint_renderer(session_,lineage_,3,map_sha_,checkpoint_,snapshot_);
  require_ok(result_,'checkpoint reconstruction baseline');

  -- Inject another pre-accept failure, then reconstruct from the durable checkpoint under generation 4.
  prepare_render(3);
  result_:=doom_unified_recover_checkpoint_renderer(session_,lineage_,4,map_sha_,checkpoint_,snapshot_);
  require_ok(result_,'checkpoint pending recovery');
  old_result_:=doom_unified_actor_accept(session_,lineage_,3,request_);
  if old_result_ not like 'ERR|%' then raise_application_error(-20000,'checkpoint old request accepted');end if;
  owner_status_:=doom_unified_actor_recovery_status(session_,lineage_,4);
  renderer_status_:=doom_retained_render_recovery_status(session_,4);
  frontiers;
  if owner_status_<>'OK|'||tic_||'|'||seq_||'|4|'||map_sha_ or
     renderer_status_<>'OK|'||tic_||'|'||seq_||'|4' then
    raise_application_error(-20000,'checkpoint recovery frontier owner='||owner_status_||
      ' renderer='||renderer_status_);end if;
  prepare_render(4);apply_accept(4);oracle_parity;
  dbms_output.put_line('UNIFIED_RECOVERY_PARITY_OK tic='||committed_tic_||' seq='||committed_seq_||
    ' generations=1,2,3,4 sql_recovery=1 checkpoint_recovery=1 old_request_rejected=2');
  cleanup;
exception when others then
  rollback;cleanup;raise;
end;
/
