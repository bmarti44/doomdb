whenever sqlerror exit failure rollback
set define off serveroutput on size unlimited feedback off
declare
  c_match constant varchar2(32):='dddddddddddddddddddddddddddddddd';
  c_zero constant varchar2(64):=rpad('0',64,'0');
  l_now timestamp with time zone:=localtimestamp at time zone 'UTC';
  l_payload raw(32767);l_batch blob;l_ready number;l_chain varchar2(64):=c_zero;
  l_header raw(32);l_count number;l_flags number;l_error number:=0;
  l_elapsed interval day to second;l_prompt_ms number;l_leases number;
  l_visible timestamp with time zone;

  procedure insert_tic(p_tic number) is
    l_hex varchar2(1):=lower(to_char(p_tic,'fmX'));
  begin
    insert into doom_match_tic(match_id,tic,membership_epoch,generation,
      membership_bitmap,neutral_bitmap,command_vector,command_sha,
      previous_state_sha,state_sha,event_sha,deadline_at,committed_at)
    values(c_match,p_tic,7,1,hextoraw('03'),hextoraw('00'),
      hextoraw(rpad('00',64,'0')),rpad(l_hex,64,l_hex),
      rpad('a',64,'a'),rpad(l_hex,64,l_hex),rpad('e',64,'e'),l_now,l_now);
  end;

  procedure publish_tic(p_tic number) is
  begin
    l_payload:=doom_mle_authority_delta.encode(p_tic,1,7,hextoraw('03'),2,
      l_chain,rpad(lower(to_char(p_tic,'fmX')),64,lower(to_char(p_tic,'fmX'))),
      hextoraw(rpad(lower(to_char(p_tic,'fmX')),64,lower(to_char(p_tic,'fmX')))));
    doom_mle_transition_transport.publish(c_match,l_payload);
    l_chain:=lower(rawtohex(utl_raw.substr(l_payload,53,32)));
  end;
begin
  update doom_match_poll_capacity set long_poll_enabled=1 where capacity_id=1;
  commit;
  delete from doom_match where match_id=c_match;
  insert into doom_match(match_id,match_state,game_mode,skill,episode,map,
    max_players,membership_epoch,generation,current_tic,host_capability_salt,
    host_capability_hash,join_capability_salt,join_capability_hash,created_at,
    last_activity_at,started_at,expires_at)
  values(c_match,'ACTIVE','COOP',3,1,1,2,7,1,2,
    hextoraw(rpad('01',64,'1')),rpad('1',64,'1'),
    hextoraw(rpad('02',64,'2')),rpad('2',64,'2'),l_now,l_now,l_now,
    l_now+interval '1' hour);
  for p in 0..1 loop
    insert into doom_match_member(match_id,player_slot,member_state,
      membership_epoch,generation,capability_epoch,capability_salt,
      capability_hash,display_name,joined_at,last_seen_at,ready_at)
    values(c_match,p,'ACTIVE',7,1,1,
      hextoraw(rpad(lower(to_char(p+3,'fmX')),64,lower(to_char(p+3,'fmX')))),
      rpad(lower(to_char(p+5,'fmX')),64,lower(to_char(p+5,'fmX'))),'PLAYER'||p,l_now,l_now,l_now);
  end loop;
  insert_tic(1);publish_tic(1);insert_tic(2);publish_tic(2);commit;

  doom_mle_transition_transport.poll_batch(c_match,0,7,1,0,64,0,l_ready,l_batch);
  l_header:=dbms_lob.substr(l_batch,32,1);
  l_flags:=to_number(rawtohex(utl_raw.substr(l_header,7,2)),'xxxx');
  l_count:=to_number(rawtohex(utl_raw.substr(l_header,9,2)),'xxxx');
  if l_ready<>1 or utl_raw.cast_to_varchar2(utl_raw.substr(l_header,1,4))<>'DMB1'
     or l_flags<>0 or l_count<>2 then
    raise_application_error(-20799,'DMB1 immediate batch');
  end if;

  doom_mle_transition_transport.poll_batch(c_match,0,7,1,2,64,10,l_ready,l_batch);
  l_header:=dbms_lob.substr(l_batch,32,1);
  l_flags:=to_number(rawtohex(utl_raw.substr(l_header,7,2)),'xxxx');
  if l_ready<>0 or l_flags<>1 then raise_application_error(-20799,'DMB1 timeout');end if;

  dbms_scheduler.create_job('DOOM_DMB1_HELD_POLL',job_type=>'PLSQL_BLOCK',
    job_action=>'declare r number;b blob;begin doom_mle_transition_transport.poll_batch('''||
      c_match||''',1,7,1,2,64,500,r,b);end;',enabled=>true,auto_drop=>true);
  for attempt in 1..100 loop
    select count(*) into l_leases from doom_match_poll_lease
      where match_id=c_match and player_slot=1;
    exit when l_leases=1;dbms_session.sleep(.01);
  end loop;
  begin
    doom_mle_transition_transport.poll_batch(c_match,1,7,1,2,64,0,l_ready,l_batch);
  exception when others then
    if instr(sqlerrm,'one outstanding poll per player')>0 then l_error:=1;else raise;end if;
  end;
  if l_error<>1 then raise_application_error(-20799,'DMB1 duplicate poll accepted');end if;

  dbms_scheduler.create_job('DOOM_DMB1_PUBLISH',job_type=>'PLSQL_BLOCK',
    job_action=>'declare p raw(32767);c varchar2(64);n timestamp with time zone:='||
      'localtimestamp at time zone ''UTC'';begin dbms_session.sleep(.1);'||
      'select chain_sha into c from doom_match_transition where match_id='''||c_match||
      ''' and tic=2;insert into doom_match_tic(match_id,tic,membership_epoch,'||
      'generation,membership_bitmap,neutral_bitmap,command_vector,command_sha,'||
      'previous_state_sha,state_sha,event_sha,deadline_at,committed_at) values('''||
      c_match||''',3,7,1,hextoraw(''03''),hextoraw(''00''),hextoraw(rpad(''00'','||
      '64,''0'')),rpad(''3'',64,''3''),rpad(''a'',64,''a''),'||
      'rpad(''3'',64,''3''),rpad(''e'',64,''e''),n,n);'||
      'p:=doom_mle_authority_delta.encode('||
      '3,1,7,hextoraw(''03''),2,c,rpad(''3'',64,''3''),'||
      'hextoraw(rpad(''03'',64,''03'')));doom_mle_transition_transport.publish('''||
      c_match||''',p);update doom_match set current_tic=3 where match_id='''||
      c_match||''';commit;update doom_match set last_activity_at='||
      'localtimestamp at time zone ''UTC'' where match_id='''||c_match||
      ''';commit;end;',enabled=>true,auto_drop=>true);
  doom_mle_transition_transport.poll_batch(c_match,0,7,1,2,64,500,l_ready,l_batch);
  for attempt in 1..100 loop
    select last_activity_at into l_visible from doom_match where match_id=c_match;
    exit when l_visible>l_now;dbms_session.sleep(.001);
  end loop;
  l_elapsed:=(localtimestamp at time zone 'UTC')-l_visible;
  l_prompt_ms:=extract(day from l_elapsed)*86400000+
    extract(hour from l_elapsed)*3600000+extract(minute from l_elapsed)*60000+
    extract(second from l_elapsed)*1000;
  if l_ready<>1 or l_prompt_ms>5 then
    raise_application_error(-20799,'DMB1 prompt return ms='||round(l_prompt_ms,3));
  end if;

  delete from doom_match where match_id=c_match;
  update doom_match_poll_capacity set long_poll_enabled=0 where capacity_id=1;
  commit;
  dbms_output.put_line('PASS DMB1 SQL transport batch=2 timeout=1 duplicate=reject'||
    ' prompt_return_ms='||round(l_prompt_ms,3)||' held_polls=4 pool_reserve=2');
exception when others then
  rollback;delete from doom_match where match_id=c_match;
  update doom_match_poll_capacity set long_poll_enabled=0 where capacity_id=1;
  commit;raise;
end;
/
