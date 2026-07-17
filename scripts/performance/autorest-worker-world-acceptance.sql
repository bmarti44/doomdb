whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  retained_ varchar2(32);oracle_ varchar2(32);payload_ blob;commands_ clob;
  pack_ raw(32767);pack_rows_ number;pack_draws_ number;
  retained_rng_ number;oracle_rng_ number;retained_tic_ number;oracle_tic_ number;
  retained_world_ clob;oracle_world_ clob;parity_ varchar2(4000);
  requests_ number;old_enabled_ number;old_parity_ number;
  procedure step_(p_session varchar2) is
  begin
    commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,'||
      '"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":0,'||
      '"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(p_session,commands_,payload_);
    if payload_ is null or dbms_lob.getlength(payload_)=0 then
      raise_application_error(-20000,'empty passive-world frame');
    end if;
  end;
  procedure force_expiry_(p_session varchar2) is
  begin
    update sector_state ss set light_timer=1
      where ss.session_token=p_session and exists(
        select 1 from doom_map_sector ms
          where ms.sector_id=ss.sector_id and ms.special=1);
  end;
  procedure read_world_(p_session varchar2,p_world out clob) is
  begin
    select json_arrayagg(json_array(ss.sector_id,ss.light_level,
      ss.light_timer null on null returning varchar2)
      order by ss.sector_id returning clob) into p_world
      from sector_state ss where ss.session_token=p_session;
  end;
  procedure cleanup_ is
  begin
    begin if retained_ is not null then doom_unified_worker.request_stop(retained_);end if;
      exception when others then null;end;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if retained_ is not null then delete from game_sessions where session_token=retained_;end if;
    if oracle_ is not null then delete from game_sessions where session_token=oracle_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config
    where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config
    where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  commit;
  doom_api.new_game(3,retained_,payload_);force_expiry_(retained_);commit;
  doom_api.new_game(3,oracle_,payload_);force_expiry_(oracle_);commit;

  doom_retained_world_pack.build(retained_,1,pack_);
  pack_rows_:=to_number(rawtohex(utl_raw.substr(pack_,7,2)),'XXXX');
  pack_draws_:=to_number(rawtohex(utl_raw.substr(pack_,11,2)),'XXXX');
  if pack_rows_=0 or pack_draws_=0 then
    raise_application_error(-20000,'forced passive-world pack did not mutate');
  end if;

  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';commit;
  step_(retained_);
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';commit;
  step_(oracle_);

  select current_tic,rng_cursor into retained_tic_,retained_rng_
    from game_sessions where session_token=retained_;
  select current_tic,rng_cursor into oracle_tic_,oracle_rng_
    from game_sessions where session_token=oracle_;
  read_world_(retained_,retained_world_);read_world_(oracle_,oracle_world_);
  select count(*),max(a.detail) into requests_,parity_
    from doom_worker_request q join doom_worker_audit a on a.request_id=q.request_id
    where q.session_token=retained_ and q.request_status='COMMITTED'
      and a.audit_event='PARITY_OK';
  if retained_tic_<>1 or oracle_tic_<>1 or retained_rng_<>oracle_rng_ or
     dbms_lob.compare(retained_world_,oracle_world_)<>0 or requests_<>1 or
     parity_ not like 'OK|%' then
    dbms_output.put_line('RETAINED_WORLD '||dbms_lob.substr(retained_world_,4000,1));
    dbms_output.put_line('ORACLE_WORLD '||dbms_lob.substr(oracle_world_,4000,1));
    raise_application_error(-20000,'passive-world retained/SQL differential mismatch');
  end if;
  dbms_output.put_line('AUTOREST_WORKER_WORLD_OK rows='||pack_rows_||
    ' draws='||pack_draws_||' rng='||retained_rng_||' parity='||parity_||
    ' bytes='||dbms_lob.getlength(payload_));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;begin
    cleanup_;
    raise_application_error(-20000,'world acceptance failed ['||code_||'] '||message_);
  end;
end;
/
exit
