whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Static deployment gate for the retained legacy=0 canonical-state codec.
-- The parity point deliberately matches the worker: SQL apply has completed,
-- Java still owns the pending tic, and accept has not yet swapped the owner.
declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);request_ varchar2(32);command_ raw(24);
  delta_ raw(32767);oracle_ blob;retained_ blob;snapshot_ blob;oracle_sha_ varchar2(64);
  retained_sha_ varchar2(4000);tic_ number;seq_ number;rng_ number;next_mobj_ number;
  committed_tic_ number;committed_seq_ number;version_ number;count_ number;delta_sha_ varchar2(64);
  generation_ number:=1;death_id_ number;projectile_id_ number;px_ number;py_ number;
  drop_rows_ number:=0;projectile_rows_ number:=0;mismatches_ number:=0;
  command_tics_ number:=0;plain_tics_ number:=0;
  old_next_ number;running_ number;started_ timestamp with time zone;
  encode_ms_ sys.odcinumberlist:=sys.odcinumberlist();blob_ms_ sys.odcinumberlist:=sys.odcinumberlist();
  total_ms_ sys.odcinumberlist:=sys.odcinumberlist();bytes_ sys.odcinumberlist:=sys.odcinumberlist();
  compare_ms_ sys.odcinumberlist:=sys.odcinumberlist();object_encode_ms_ sys.odcinumberlist:=sys.odcinumberlist();
  changed_ sys.odcinumberlist:=sys.odcinumberlist();reused_ sys.odcinumberlist:=sys.odcinumberlist();
  removed_ sys.odcinumberlist:=sys.odcinumberlist();
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  diff_ number;oracle_piece_ raw(64);retained_piece_ raw(64);
  diff_id_ number;oracle_number_ varchar2(200);retained_number_ varchar2(200);
  oracle_numeric_ number;retained_numeric_ number;
  diff_ord_ number;oracle_id_ number;retained_id_ number;
  function elapsed_ms(p_start timestamp with time zone) return number is d interval day to second;
  begin d:=systimestamp-p_start;return extract(day from d)*86400000+extract(hour from d)*3600000+
    extract(minute from d)*60000+extract(second from d)*1000;end;
  procedure add_(p_values in out nocopy sys.odcinumberlist,p_value number) is
  begin p_values.extend;p_values(p_values.count):=p_value;end;
  procedure report_(p_name varchar2,p_values sys.odcinumberlist) is p50 number;p95 number;pmax number;
  begin select percentile_cont(.5) within group(order by column_value),
      percentile_cont(.95) within group(order by column_value),max(column_value)
      into p50,p95,pmax from table(p_values);
    dbms_output.put_line(p_name||'='||round(p50,3)||'|'||round(p95,3)||'|'||round(pmax,3));
  end;
  procedure cleanup_ is
  begin
    if session_ is not null then delete from game_sessions where session_token=session_;commit;end if;
  exception when others then rollback;
  end;
begin
  doom_api.new_game(3,session_,payload_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=session_;
  select p.x,p.y into px_,py_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id
    where g.session_token=session_;
  update players set health=1000000 where session_token=session_ and player_id=(
    select current_player_id from game_sessions where session_token=session_);
  update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d
      where d.thing_type=m.thing_type),state_tics=0,awake=1,attack_cooldown=1,
      health=greatest(10,health),monster_health_seen=greatest(10,health),death_processed=0
    where session_token=session_ and exists(
      select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select min(m.mobj_id) into death_id_ from mobjs m join doom_monster_def d
    on d.thing_type=m.thing_type where m.session_token=session_ and d.drop_thing_type is not null;
  select min(m.mobj_id) into projectile_id_ from mobjs m join doom_monster_def d
    on d.thing_type=m.thing_type where m.session_token=session_ and d.attack_kind='PROJECTILE'
      and m.mobj_id<>death_id_;
  update mobjs set health=0,death_processed=0 where session_token=session_ and mobj_id=death_id_;
  update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_))
      where rownum=1),state_id=(select d.missile_state_id from doom_monster_def d
      where d.thing_type=m.thing_type),state_tics=0,awake=1,attack_cooldown=0,
      target_mobj_id=(select current_player_id from game_sessions where session_token=session_)
    where session_token=session_ and mobj_id=projectile_id_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_clob_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  dbms_lob.createtemporary(snapshot_,true,dbms_lob.call);doom_renderer_snapshot_fill(session_,snapshot_);
  result_:=doom_unified_recover_sql_renderer(session_,lineage_,generation_,map_sha_,snapshot_);
  if result_ not like 'OK|%' then raise_application_error(-20000,'retained state load '||result_);end if;
  dbms_lob.createtemporary(oracle_,true,dbms_lob.call);
  dbms_lob.createtemporary(retained_,true,dbms_lob.call);

  for sample_ in 1..300 loop
    command_:=hextoraw('444d53430201000000000000'||lpad(to_char(seq_+1,'fmxxxxxxxx'),8,'0')||
      case mod(sample_,17) when 0 then '01' when 8 then 'ff' else '00' end||
      case mod(sample_,2) when 0 then '01' else 'ff' end||
      case when mod(sample_,19)=0 then '01' else '00' end||
      case when mod(sample_,5)=0 then '01' else '00' end||'00000000');
    request_:=lower(rawtohex(sys_guid()));old_next_:=next_mobj_;
    if mod(sample_,37)=0 then
      delta_:=doom_unified_actor_prepare(session_,lineage_,generation_,request_,'TIC',tic_,seq_,
        rng_,next_mobj_,0);plain_tics_:=plain_tics_+1;
      if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000400' then
        raise_application_error(-20000,'retained plain TIC prepare '||sample_||' '||doom_unified_actor_last_error);end if;
      doom_unified_delta_apply.apply_tic(session_,lineage_,tic_,seq_,delta_,committed_tic_,
        committed_seq_,version_,count_,delta_sha_);
    else
      delta_:=doom_unified_command_tic_prepare(session_,lineage_,generation_,request_,tic_,seq_,
        rng_,next_mobj_,0,command_);command_tics_:=command_tics_+1;
      if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000500' then
        raise_application_error(-20000,'retained command TIC prepare '||sample_||' '||doom_unified_actor_last_error);end if;
      doom_unified_delta_apply.apply_command_tic(session_,lineage_,tic_,seq_,command_,delta_,
        committed_tic_,committed_seq_,version_,count_,delta_sha_);
    end if;

    doom_canonical_state.build_into_locator(session_,0,oracle_,oracle_sha_);
    started_:=systimestamp;
    retained_sha_:=doom_unified_state_fill(session_,lineage_,generation_,request_,retained_);
    add_(total_ms_,elapsed_ms(started_));
    add_(encode_ms_,doom_unified_state_encode_ns/1000000);
    add_(blob_ms_,doom_unified_state_blob_ns/1000000);
    add_(compare_ms_,doom_unified_state_compare_ns/1000000);
    add_(object_encode_ms_,doom_unified_state_object_encode_ns/1000000);
    add_(changed_,doom_unified_state_changed);add_(reused_,doom_unified_state_reused);
    add_(removed_,doom_unified_state_removed);
    add_(bytes_,dbms_lob.getlength(retained_));
    if retained_sha_<>oracle_sha_ or dbms_lob.getlength(retained_)<>dbms_lob.getlength(oracle_) or
       dbms_lob.compare(retained_,oracle_)<>0 or
       lower(rawtohex(dbms_crypto.hash(retained_,dbms_crypto.hash_sh256)))<>retained_sha_ then
      mismatches_:=mismatches_+1;
      diff_:=1;
      while diff_<=least(dbms_lob.getlength(oracle_),dbms_lob.getlength(retained_)) loop
        exit when dbms_lob.substr(oracle_,1,diff_)<>dbms_lob.substr(retained_,1,diff_);
        diff_:=diff_+1;
      end loop;
      oracle_piece_:=dbms_lob.substr(oracle_,32,greatest(1,diff_-8));
      retained_piece_:=dbms_lob.substr(retained_,32,greatest(1,diff_-8));
      begin
        select o.mobj_id,o.momentum_x,r.momentum_x
          into diff_id_,oracle_numeric_,retained_numeric_
        from json_table(oracle_,'$.mobjs[*]' columns(
          mobj_id number path '$.mobj_id',momentum_x number path '$.momentum_x')) o
        join json_table(retained_,'$.mobjs[*]' columns(
          mobj_id number path '$.mobj_id',momentum_x number path '$.momentum_x')) r
          on r.mobj_id=o.mobj_id
        where o.momentum_x<>r.momentum_x and rownum=1;
        oracle_number_:=to_char(oracle_numeric_,'TM9','NLS_NUMERIC_CHARACTERS=''.,''');
        retained_number_:=to_char(retained_numeric_,'TM9','NLS_NUMERIC_CHARACTERS=''.,''');
      exception when no_data_found then diff_id_:=null;end;
      begin
        select o.ord,json_value(o.obj,'$.mobj_id' returning number),
          json_value(r.obj,'$.mobj_id' returning number),
          regexp_substr(dbms_lob.substr(o.obj,4000,1),'"momentum_x":[^,}]+'),
          regexp_substr(dbms_lob.substr(r.obj,4000,1),'"momentum_x":[^,}]+')
          into diff_ord_,oracle_id_,retained_id_,oracle_number_,retained_number_
        from json_table(oracle_,'$.mobjs[*]' columns(
          ord for ordinality,obj clob format json path '$')) o
        join json_table(retained_,'$.mobjs[*]' columns(
          ord for ordinality,obj clob format json path '$')) r on r.ord=o.ord
        where dbms_lob.compare(o.obj,r.obj)<>0 and rownum=1;
      exception when no_data_found then diff_ord_:=null;end;
      raise_application_error(-20000,'retained state mismatch tic='||committed_tic_||
        ' offset='||diff_||' lengths='||dbms_lob.getlength(oracle_)||'|'||
        dbms_lob.getlength(retained_)||' oracle_bytes='||rawtohex(oracle_piece_)||
        ' retained_bytes='||rawtohex(retained_piece_)||' mobj='||diff_id_||
        ' numbers='||oracle_number_||'|'||retained_number_||' ord='||diff_ord_||
        ' ids='||oracle_id_||'|'||retained_id_);
    end if;
    select count(case when projectile_kind is null then 1 end),
      count(case when projectile_kind is not null then 1 end)
      into running_,count_ from mobjs where session_token=session_ and mobj_id>=old_next_;
    drop_rows_:=drop_rows_+running_;projectile_rows_:=projectile_rows_+count_;
    commit;
    result_:=doom_unified_actor_accept(session_,lineage_,generation_,request_);
    if result_<>'OK' then raise_application_error(-20000,'retained state accept '||sample_||' '||result_);end if;
    tic_:=committed_tic_;seq_:=committed_seq_;
    select rng_cursor into rng_ from game_sessions where session_token=session_;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;

    if sample_=150 then
      generation_:=generation_+1;doom_renderer_snapshot_fill(session_,snapshot_);
      result_:=doom_unified_recover_sql_renderer(session_,lineage_,generation_,map_sha_,snapshot_);
      if result_ not like 'OK|%' then raise_application_error(-20000,'retained state recovery '||result_);end if;
    end if;
  end loop;
  if drop_rows_=0 or projectile_rows_=0 then
    raise_application_error(-20000,'retained state spawn coverage drops='||drop_rows_||
      ' projectiles='||projectile_rows_);end if;
  dbms_output.put_line('RETAINED_STATE_CODEC_OK tics=300 mismatches='||mismatches_||
    ' recoveries=1 drops='||drop_rows_||' projectiles='||projectile_rows_||
    ' command_tics='||command_tics_||' plain_tics='||plain_tics_||
    ' frontier='||tic_||'|'||seq_||' generation='||generation_);
  report_('retained_state_total_ms',total_ms_);report_('retained_state_encode_ms',encode_ms_);
  report_('retained_state_blob_ms',blob_ms_);report_('retained_state_bytes',bytes_);
  report_('retained_state_compare_ms',compare_ms_);report_('retained_state_object_encode_ms',object_encode_ms_);
  report_('retained_state_changed',changed_);report_('retained_state_reused',reused_);
  report_('retained_state_removed',removed_);
  cleanup_;
exception when others then rollback;cleanup_;raise;
end;
/

exit
