whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);request_ varchar2(32);command_ raw(24);delta_ raw(32767);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;committed_tic_ number;committed_seq_ number;
  version_ number;count_ number;sha_ varchar2(64);restart_ blob;
  prepare_ms_ sys.odcinumberlist:=sys.odcinumberlist();apply_ms_ sys.odcinumberlist:=sys.odcinumberlist();
  commit_ms_ sys.odcinumberlist:=sys.odcinumberlist();accept_ms_ sys.odcinumberlist:=sys.odcinumberlist();
  total_ms_ sys.odcinumberlist:=sys.odcinumberlist();started_ timestamp with time zone;
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  function int_(p raw,o pls_integer) return binary_integer is
  begin return utl_raw.cast_to_binary_integer(utl_raw.substr(p,o,4),utl_raw.big_endian);end;
  function elapsed_ms(p_start timestamp with time zone) return number is d_ interval day to second;
  begin d_:=systimestamp-p_start;return extract(day from d_)*86400000+extract(hour from d_)*3600000+
    extract(minute from d_)*60000+extract(second from d_)*1000;end;
  procedure sample(p_values in out nocopy sys.odcinumberlist,p_start timestamp with time zone) is
  begin p_values.extend;p_values(p_values.count):=elapsed_ms(p_start);end;
  procedure report(p_name varchar2,p_values sys.odcinumberlist) is p50_ number;p95_ number;max_ number;
  begin select percentile_cont(.5) within group(order by column_value),
      percentile_cont(.95) within group(order by column_value),max(column_value)
      into p50_,p95_,max_ from table(p_values);
    dbms_output.put_line(p_name||'_ms='||round(p50_,3)||'|'||round(p95_,3)||'|'||round(max_,3));
  end;
  procedure report_warm(p_name varchar2,p_values sys.odcinumberlist) is
    warm_ sys.odcinumberlist:=sys.odcinumberlist();
  begin
    for i in 2..p_values.count loop warm_.extend;warm_(warm_.count):=p_values(i);end loop;
    report(p_name,warm_);
  end;
  procedure cleanup is begin
    if session_ is not null then delete from game_sessions where session_token=session_;commit;end if;
  end;
begin
  doom_api.new_game(3,session_,payload_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
  if result_ not like 'OK|%' then raise_application_error(-20000,'transaction benchmark load '||result_);end if;

  for command_seq_ in 1..300 loop
    command_:=hextoraw('444d53430201000000000000'||lpad(to_char(command_seq_,'fmxxxxxxxx'),8,'0')||
      case mod(command_seq_,17) when 0 then '01' when 8 then 'ff' else '00' end||
      case mod(command_seq_,2) when 0 then '01' else 'ff' end||
      case when mod(command_seq_,19)=0 then '01' else '00' end||
      case when mod(command_seq_,5)=0 then '01' else '00' end||'00000000');
    request_:=lower(rawtohex(sys_guid()));started_:=systimestamp;
    declare phase_ timestamp with time zone:=systimestamp;begin
      delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
      if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000500' then
        raise_application_error(-20000,'transaction prepare '||command_seq_||' '||doom_unified_actor_last_error);end if;
      sample(prepare_ms_,phase_);
    end;
    declare phase_ timestamp with time zone:=systimestamp;begin
      doom_unified_delta_apply.apply_command_tic(session_,lineage_,tic_,seq_,command_,delta_,
        committed_tic_,committed_seq_,version_,count_,sha_);sample(apply_ms_,phase_);
    end;
    declare phase_ timestamp with time zone:=systimestamp;begin commit;sample(commit_ms_,phase_);end;
    declare phase_ timestamp with time zone:=systimestamp;begin
      result_:=doom_unified_actor_accept(session_,lineage_,1,request_);
      if result_<>'OK' then raise_application_error(-20000,'transaction accept '||command_seq_||' '||result_);end if;
      sample(accept_ms_,phase_);
    end;
    sample(total_ms_,started_);tic_:=committed_tic_;seq_:=committed_seq_;
    rng_:=int_(delta_,134);next_mobj_:=int_(delta_,154);
  end loop;

  if tic_<>300 or seq_<>300 then raise_application_error(-20000,'transaction output frontier');end if;
  select current_tic,last_command_seq,rng_cursor into committed_tic_,committed_seq_,version_
    from game_sessions where session_token=session_;
  if committed_tic_<>tic_ or committed_seq_<>seq_ or version_<>rng_ then
    raise_application_error(-20000,'transaction SQL frontier');end if;
  result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|300|300|%' then raise_application_error(-20000,'transaction owner parity '||result_);end if;
  dbms_lob.createtemporary(restart_,true,dbms_lob.call);
  result_:=doom_unified_world_checkpoint(session_,lineage_,1,restart_);
  if result_ not like 'OK|%' then raise_application_error(-20000,'transaction checkpoint '||result_);end if;
  result_:=doom_unified_world_restore(session_,lineage_,1,restart_);
  if result_ not like 'OK|%' then raise_application_error(-20000,'transaction restore '||result_);end if;
  result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|300|300|%' then raise_application_error(-20000,'transaction restart parity '||result_);end if;

  dbms_output.put_line('UNIFIED_COMMAND_TRANSACTION_OK commands=300 frontier='||tic_||'|'||seq_||
    ' bytes='||utl_raw.length(delta_)||' restart='||dbms_lob.getlength(restart_));
  report('prepare',prepare_ms_);report('strict_sql_apply',apply_ms_);report('commit_log_sync',commit_ms_);
  dbms_output.put_line('strict_sql_apply_cold_ms='||round(apply_ms_(1),3));
  report_warm('strict_sql_apply_warm',apply_ms_);
  report('java_accept',accept_ms_);report('transaction_total',total_ms_);
  cleanup;
exception when others then rollback;cleanup;raise;
end;
/
