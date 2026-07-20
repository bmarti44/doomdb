whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  id_ constant varchar2(32):='13131313131313131313131313131313';
  now_ timestamp with time zone:=systimestamp;
  count_ number;

  procedure expect_check_(statement_ varchar2,label_ varchar2) is
  begin
    execute immediate statement_;
    raise_application_error(-20000,label_||' unexpectedly succeeded');
  exception when others then
    if sqlcode=-20000 then raise;end if;
    if sqlcode<>-2290 then
      raise_application_error(-20000,label_||' wrong error '||sqlcode);
    end if;
  end;
begin
  delete from doom_match where match_id=id_;
  insert into doom_match(
    match_id,match_state,game_mode,skill,episode,map,max_players,
    membership_epoch,generation,current_tic,
    host_capability_salt,host_capability_hash,
    join_capability_salt,join_capability_hash,
    created_at,last_activity_at,expires_at)
  values(id_,'LOBBY','COOP',3,1,1,2,1,0,0,
    hextoraw(rpad('01',64,'01')),rpad('1',64,'1'),
    hextoraw(rpad('02',64,'02')),rpad('2',64,'2'),
    now_,now_,now_+interval '1' hour);

  insert into doom_match_member(
    match_id,player_slot,member_state,membership_epoch,generation,
    capability_epoch,capability_salt,capability_hash,display_name,
    joined_at,last_seen_at)
  values(id_,0,'READY',1,0,1,hextoraw(rpad('03',64,'03')),
    rpad('3',64,'3'),'HOST',now_,now_);
  insert into doom_match_member(
    match_id,player_slot,member_state,membership_epoch,generation,
    capability_epoch,capability_salt,capability_hash,display_name,
    joined_at,last_seen_at)
  values(id_,1,'READY',1,0,1,hextoraw(rpad('04',64,'04')),
    rpad('4',64,'4'),'JOINER',now_,now_);

  update doom_match set match_state='ACTIVE',generation=1,started_at=now_
    where match_id=id_ and match_state='LOBBY' and membership_epoch=1;
  update doom_match_member set member_state='ACTIVE',generation=1
    where match_id=id_ and membership_epoch=1 and generation=0;

  insert into doom_match_command(
    match_id,tic,player_slot,command_seq,membership_epoch,generation,
    command_source,ticcmd_raw,command_sha,submitted_at,accepted_at)
  values(id_,1,0,1,1,1,'SUBMITTED',hextoraw('0000000000000000'),
    rpad('5',64,'5'),now_,now_);
  insert into doom_match_command(
    match_id,tic,player_slot,command_seq,membership_epoch,generation,
    command_source,ticcmd_raw,command_sha,submitted_at,accepted_at)
  values(id_,1,1,1,1,1,'NEUTRAL_DEADLINE',hextoraw('0000000000000000'),
    rpad('6',64,'6'),now_,now_);
  insert into doom_match_tic(
    match_id,tic,membership_epoch,generation,membership_bitmap,neutral_bitmap,
    command_vector,command_sha,previous_state_sha,state_sha,event_sha,
    deadline_at,committed_at)
  values(id_,1,1,1,hextoraw('03'),hextoraw('02'),
    hextoraw(rpad('00',64,'00')),rpad('7',64,'7'),rpad('8',64,'8'),
    rpad('9',64,'9'),rpad('a',64,'a'),now_,now_);
  insert into doom_match_frame(
    match_id,tic,player_slot,membership_epoch,generation,frame_sha,
    response_sha,response_bytes,response_blob,created_at)
  values(id_,1,0,1,1,rpad('b',64,'b'),rpad('c',64,'c'),1,empty_blob(),now_);
  insert into doom_match_checkpoint(
    match_id,tic,membership_epoch,generation,membership_bitmap,command_sha,
    state_sha,checkpoint_sha,checkpoint_bytes,checkpoint_blob,created_at)
  values(id_,1,1,1,hextoraw('03'),rpad('7',64,'7'),rpad('9',64,'9'),
    rpad('d',64,'d'),1,empty_blob(),now_);

  expect_check_(
    'insert into doom_match_member(match_id,player_slot,member_state,'||
    'membership_epoch,generation,capability_epoch,capability_salt,'||
    'capability_hash,display_name,joined_at,last_seen_at) values('''||id_||
    ''',4,''JOINED'',1,1,1,hextoraw('''||rpad('05',64,'05')||'''),'''||
    rpad('e',64,'e')||''',''BAD'',systimestamp,systimestamp)',
    'slot fence');
  expect_check_(
    'insert into doom_match_command(match_id,tic,player_slot,command_seq,'||
    'membership_epoch,generation,command_source,ticcmd_raw,command_sha,'||
    'submitted_at,accepted_at) values('''||id_||
    ''',2,0,2,1,0,''SUBMITTED'',hextoraw(''0000000000000000''),'''||
    rpad('f',64,'f')||''',systimestamp,systimestamp)',
    'generation fence');

  delete from doom_match where match_id=id_;
  select (select count(*) from doom_match_member where match_id=id_)+
         (select count(*) from doom_match_command where match_id=id_)+
         (select count(*) from doom_match_tic where match_id=id_)+
         (select count(*) from doom_match_frame where match_id=id_)+
         (select count(*) from doom_match_checkpoint where match_id=id_)
    into count_ from dual;
  if count_<>0 then raise_application_error(-20000,'cascade rows='||count_);end if;
  rollback;
  dbms_output.put_line('PASS P13.1-MULTIPLAYER-SCHEMA-LIVE fences/cascades');
exception when others then
  rollback;
  raise;
end;
/
