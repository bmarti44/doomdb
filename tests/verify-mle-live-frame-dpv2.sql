whenever sqlerror exit failure rollback
set define off
set serveroutput on

declare
  c_match constant varchar2(32):='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
  l_now timestamp with time zone:=systimestamp;
  l_source blob;
  l_target blob;
  l_wire blob;
  l_raw blob;
  l_count number;
  l_first number;
  l_last number;
  l_chunk raw(16000);
  l_header raw(16);
  l_record raw(8);
  l_failed boolean:=false;

  procedure append_frame(p_value in raw) is
  begin
    l_chunk:=utl_raw.copies(p_value,16000);
    for l_part in 1..4 loop
      dbms_lob.writeappend(l_source,16000,l_chunk);
    end loop;
  end append_frame;

  procedure assert_wire(
    p_slot in number,p_after in number,p_max in number,
    p_expected_count in number,p_expected_first in number,
    p_expected_value in varchar2
  ) is
    l_local blob;
    l_unpacked blob;
    l_local_count number;
    l_local_first number;
    l_local_last number;
  begin
    doom_mle_live_frame_transport.poll_batch(
      c_match,p_slot,1,1,p_after,p_max,
      l_local_count,l_local_first,l_local_last,l_local);
    if l_local_count<>p_expected_count
       or l_local_first<>p_expected_first
       or l_local_last<>p_expected_first+p_expected_count-1 then
      raise_application_error(
        -20998,'DPV2 frontier extraction mismatch');
    end if;
    l_unpacked:=utl_compress.lz_uncompress(l_local);
    if dbms_lob.getlength(l_unpacked)<>8+p_expected_count*64008
       or dbms_lob.substr(l_unpacked,4,1)<>hextoraw('44504232')
       or to_number(rawtohex(dbms_lob.substr(l_unpacked,4,5)),'XXXXXXXX')
            <>p_expected_count
       or dbms_lob.substr(l_unpacked,1,17)<>hextoraw(p_expected_value)
       or dbms_lob.substr(l_unpacked,1,64016)<>hextoraw(p_expected_value) then
      raise_application_error(-20997,'DPV2 authenticated pixels mismatch');
    end if;
    if dbms_lob.istemporary(l_unpacked)=1 then
      dbms_lob.freetemporary(l_unpacked);
    end if;
    if dbms_lob.istemporary(l_local)=1 then
      dbms_lob.freetemporary(l_local);
    end if;
  end assert_wire;
begin
  delete from doom_match where match_id=c_match;
  insert into doom_match(
    match_id,match_state,game_mode,skill,episode,map,max_players,
    membership_epoch,generation,current_tic,
    host_capability_salt,host_capability_hash,
    join_capability_salt,join_capability_hash,
    created_at,last_activity_at,expires_at)
  values(
    c_match,'ACTIVE','COOP',3,1,1,2,1,1,3,
    hextoraw(rpad('11',64,'11')),rpad('1',64,'1'),
    hextoraw(rpad('22',64,'22')),rpad('2',64,'2'),
    l_now,l_now,l_now+interval '1' hour);
  for l_slot in 0..1 loop
    insert into doom_match_member(
      match_id,player_slot,member_state,membership_epoch,generation,
      capability_epoch,capability_salt,capability_hash,display_name,
      joined_at,last_seen_at,ready_at)
    values(
      c_match,l_slot,'ACTIVE',1,1,1,
      hextoraw(rpad(case l_slot when 0 then '33' else '44' end,64,
        case l_slot when 0 then '33' else '44' end)),
      rpad(case l_slot when 0 then '3' else '4' end,64,
        case l_slot when 0 then '3' else '4' end),
      'DPV2-'||l_slot,l_now,l_now,l_now);
  end loop;
  doom_mle_live_frame_transport.initialize_ring(c_match,2,1,1);

  dbms_lob.createtemporary(l_source,true,dbms_lob.call);
  dbms_lob.writeappend(
    l_source,16,hextoraw('44505632000000010000000303000000'));
  for l_tic in 1..3 loop
    l_record:=hextoraw(
      lpad(to_char(l_tic,'FMXXXXXXXX'),8,'0')||
      lpad(to_char(l_tic,'FMXX'),2,'0')||
      lpad(to_char(l_tic+3,'FMXX'),2,'0')||'01'||'00');
    dbms_lob.writeappend(l_source,8,l_record);
    append_frame(hextoraw(lpad(to_char(16+l_tic,'FMXX'),2,'0')));
    append_frame(hextoraw(lpad(to_char(32+l_tic,'FMXX'),2,'0')));
  end loop;
  update doom_match_live_frame_views
     set tic=3,player_mask=3,payload_bytes=dbms_lob.getlength(l_source),
         payload_blob=empty_blob(),published_at=systimestamp
   where match_id=c_match and ring_slot=3
     and membership_epoch=1 and generation=1
  returning payload_blob into l_target;
  dbms_lob.copy(l_target,l_source,dbms_lob.getlength(l_source),1,1);

  assert_wire(0,0,8,3,1,'11');
  assert_wire(1,0,8,3,1,'21');
  assert_wire(0,1,1,1,2,'12');

  -- A payload that still carries the DPV2 discriminator must fail closed;
  -- it may not fall through to a legacy row after validation starts.
  dbms_lob.write(l_target,1,14,hextoraw('FF'));
  begin
    doom_mle_live_frame_transport.poll_batch(
      c_match,0,1,1,0,8,l_count,l_first,l_last,l_wire);
  exception
    when others then
      if sqlcode=-20796 and sqlerrm like '%persistent DPV2 header mismatch%'
      then l_failed:=true; else raise; end if;
  end;
  if not l_failed then
    raise_application_error(-20996,'malformed DPV2 did not fail closed');
  end if;

  dbms_output.put_line(
    'PMLE_DPV2_TRANSPORT|PASS|frames=3|players=2'
      ||'|suffix=PASS|authentication=PASS|malformed=REJECTED');
  if dbms_lob.istemporary(l_source)=1 then
    dbms_lob.freetemporary(l_source);
  end if;
  rollback;
end;
/
