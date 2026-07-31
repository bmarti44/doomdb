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

  procedure assert_native_materialized(
    p_slot in number,p_phase1 in varchar2,p_phase2 in varchar2,
    p_current in varchar2
  ) is
    l_local blob;
    l_unpacked blob;
    l_local_count number;
    l_local_first number;
    l_local_last number;
  begin
    doom_mle_live_frame_transport.poll_batch(
      c_match,p_slot,1,1,1,8,
      l_local_count,l_local_first,l_local_last,l_local);
    l_unpacked:=utl_compress.lz_uncompress(l_local);
    dbms_output.put_line(
      'PMLE_EPT1_SAMPLE|slot='||p_slot
        ||'|phase1='||rawtohex(dbms_lob.substr(l_unpacked,3,17))
        ||'|phase2='||rawtohex(dbms_lob.substr(l_unpacked,3,64025))
        ||'|exact='||rawtohex(dbms_lob.substr(l_unpacked,3,128033)));
    if l_local_count<>3 or l_local_first<>2 or l_local_last<>4
       or dbms_lob.getlength(l_unpacked)<>8+3*64008
       -- Phase 1, tic 2: previous/current/previous at pixels 0/1/2.
       or rawtohex(dbms_lob.substr(l_unpacked,3,17))
            <>p_phase1
       -- Phase 2, tic 3: current/current/previous at pixels 0/1/2.
       or rawtohex(dbms_lob.substr(l_unpacked,3,64025))
            <>p_phase2
       or rawtohex(dbms_lob.substr(l_unpacked,3,128033))
            <>p_current||p_current||p_current then
      raise_application_error(
        -20995,'native EPT1 temporal materialization mismatch');
    end if;
    if dbms_lob.istemporary(l_unpacked)=1 then
      dbms_lob.freetemporary(l_unpacked);
    end if;
    if dbms_lob.istemporary(l_local)=1 then
      dbms_lob.freetemporary(l_local);
    end if;
  end assert_native_materialized;
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
  update doom_match_live_frame_views
     set tic=-1,player_mask=0,payload_bytes=0,payload_blob=empty_blob(),
         published_at=null
   where match_id=c_match and ring_slot=3;

  -- Replace the row with two exact MLE endpoint frames. The package must
  -- reproduce the former JS interval-three phase mask byte-for-byte in
  -- native UTL_RAW operations and leave a normal authenticated DPV2 row.
  dbms_lob.trim(l_source,0);
  dbms_lob.writeappend(
    l_source,16,hextoraw('45505431000000010000000403030000'));
  dbms_lob.writeappend(l_source,4,hextoraw('01040100'));
  append_frame(hextoraw('11'));
  append_frame(hextoraw('21'));
  dbms_lob.writeappend(l_source,4,hextoraw('01040100'));
  append_frame(hextoraw('14'));
  append_frame(hextoraw('24'));
  update doom_match_live_frame_views
     set tic=4,player_mask=3,payload_bytes=dbms_lob.getlength(l_source),
         payload_blob=empty_blob(),published_at=systimestamp
   where match_id=c_match and ring_slot=4
     and membership_epoch=1 and generation=1
  returning payload_blob into l_target;
  dbms_lob.copy(l_target,l_source,dbms_lob.getlength(l_source),1,1);
  doom_mle_live_frame_transport.materialize_temporal_bundle(
    c_match,1,1,4);
  select payload_blob into l_target
    from doom_match_live_frame_views
   where match_id=c_match and ring_slot=4;
  if dbms_lob.substr(l_target,4,1)<>hextoraw('44505632') then
    raise_application_error(-20994,'EPT1 was not replaced by DPV2');
  end if;
  assert_native_materialized(0,'111411','141411','14');
  -- Player 1 begins at global pixel 64,000, whose modulo-three phase is one.
  assert_native_materialized(1,'242121','242124','24');

  -- A palette transition retains temporal pixels: phase one uses the prior
  -- palette, phase two the current palette, and only a true layout transition
  -- falls back to copying the current exact frame.
  dbms_lob.trim(l_source,0);
  dbms_lob.writeappend(
    l_source,16,hextoraw('45505431000000040000000703030000'));
  dbms_lob.writeappend(l_source,4,hextoraw('01040100'));
  append_frame(hextoraw('14'));
  append_frame(hextoraw('24'));
  dbms_lob.writeappend(l_source,4,hextoraw('02050100'));
  append_frame(hextoraw('17'));
  append_frame(hextoraw('27'));
  update doom_match_live_frame_views
     set tic=7,player_mask=3,payload_bytes=dbms_lob.getlength(l_source),
         payload_blob=empty_blob(),published_at=systimestamp
   where match_id=c_match and ring_slot=7
     and membership_epoch=1 and generation=1
  returning payload_blob into l_wire;
  dbms_lob.copy(l_wire,l_source,dbms_lob.getlength(l_source),1,1);
  doom_mle_live_frame_transport.materialize_temporal_bundle(
    c_match,1,1,7);
  select payload_blob into l_target
    from doom_match_live_frame_views
   where match_id=c_match and ring_slot=7;
  if dbms_lob.substr(l_target,1,21)<>hextoraw('01')
     or dbms_lob.substr(l_target,1,128029)<>hextoraw('02')
     or rawtohex(dbms_lob.substr(l_target,3,25))<>'141714'
     or rawtohex(dbms_lob.substr(l_target,3,128033))<>'171714'
     or rawtohex(dbms_lob.substr(l_target,3,64025))<>'272424'
     or rawtohex(dbms_lob.substr(l_target,3,192033))<>'272427' then
    raise_application_error(
      -20991,'palette-aware temporal materialization mismatch');
  end if;

  -- A tail longer than one temporal interval must cross one ORDS response.
  doom_mle_live_frame_transport.poll_batch(
    c_match,0,1,1,1,6,l_count,l_first,l_last,l_wire);
  l_raw:=utl_compress.lz_uncompress(l_wire);
  if l_count<>6 or l_first<>2 or l_last<>7
     or dbms_lob.getlength(l_raw)<>8+6*64008
     or dbms_lob.substr(l_raw,8,1)<>hextoraw('4450423200000006') then
    raise_application_error(
      -20992,'multiple DPV2 locators were not batched');
  end if;
  if dbms_lob.istemporary(l_raw)=1 then dbms_lob.freetemporary(l_raw);end if;
  if dbms_lob.istemporary(l_wire)=1 then
    dbms_lob.freetemporary(l_wire);
  end if;

  -- A foreign-format row that becomes visible after the DPV2 statement must
  -- not enter the legacy DPD1 fallback. This is the statement-snapshot shape
  -- of the production worker-commit race.
  dbms_lob.write(l_source,4,1,hextoraw('DEADBEEF'));
  update doom_match_live_frame_views
     set tic=8,player_mask=3,payload_bytes=dbms_lob.getlength(l_source),
         payload_blob=empty_blob(),published_at=systimestamp
   where match_id=c_match and ring_slot=8
     and membership_epoch=1 and generation=1
  returning payload_blob into l_wire;
  dbms_lob.copy(l_wire,l_source,dbms_lob.getlength(l_source),1,1);
  doom_mle_live_frame_transport.poll_batch(
    c_match,0,1,1,7,8,l_count,l_first,l_last,l_wire);
  if l_count<>0 or l_first is not null or l_last is not null
     or l_wire is not null then
    raise_application_error(
      -20993,'foreign-format row entered DPD1 fallback');
  end if;

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
      ||'|suffix=PASS|authentication=PASS'
      ||'|ept1_native_exact=PASS|palette_temporal=PASS'
      ||'|multi_locator_batch=PASS'
      ||'|fallback_race=IGNORED'
      ||'|malformed=REJECTED');
  if dbms_lob.istemporary(l_source)=1 then
    dbms_lob.freetemporary(l_source);
  end if;
  rollback;
end;
/
