whenever sqlerror exit failure rollback
set define off

-- Existing installations originally constrained the shared-view ring to one
-- DPD1 tic. DPV2 adds one-to-six consecutive records while retaining the
-- original exact DPD1 size. Payload magic and every record are validated by
-- the authenticated read facade before any pixels are returned.
alter table doom_match_live_frame_views
  drop constraint doom_match_live_frame_views_slot_ck;
alter table doom_match_live_frame_views modify ring_slot number(3);
alter table doom_match_live_frame_views
  add constraint doom_match_live_frame_views_slot_ck check(
    ring_slot between 0 and 127 and player_mask in(0,1,2,3));
alter table doom_match_live_frame
  drop constraint doom_match_live_frame_slot_ck;
alter table doom_match_live_frame modify ring_slot number(3);
alter table doom_match_live_frame
  add constraint doom_match_live_frame_slot_ck check(
    player_slot between 0 and 3 and ring_slot between 0 and 127
    and palette_index between 0 and 13);
alter table doom_match_live_frame_batch
  drop constraint doom_match_live_frame_batch_slot_ck;
alter table doom_match_live_frame_batch modify ring_slot number(3);
alter table doom_match_live_frame_batch
  add constraint doom_match_live_frame_batch_slot_ck check(
    player_slot between 0 and 3 and ring_slot between 0 and 127);
alter table doom_match_live_frame_views
  drop constraint doom_match_live_frame_views_fence_ck;
alter table doom_match_live_frame_views
  add constraint doom_match_live_frame_views_fence_ck check(
    membership_epoch>0 and generation>0 and
    ((tic=-1 and player_mask=0 and payload_bytes=0
       and published_at is null) or
     (tic>=0 and player_mask in(1,2,3)
       and (payload_bytes=16+
              case player_mask when 3 then 128000 else 64000 end
         or payload_bytes=24+
              2*case player_mask when 3 then 128000 else 64000 end
         or (payload_bytes between
               16+(8+case player_mask
                 when 3 then 128000 else 64000 end)
             and
               16+6*(8+case player_mask
                 when 3 then 128000 else 64000 end)
             and mod(
               payload_bytes-16,
               8+case player_mask
                 when 3 then 128000 else 64000 end)=0))
       and published_at is not null)));

-- The worker owns writes and transaction durability.  REST receives only an
-- authenticated, generation-fenced read facade through DOOM_API.
create or replace package doom_mle_live_frame_transport authid definer as
  procedure initialize_ring(
    p_match in varchar2,p_players in number,
    p_membership_epoch in number,p_generation in number);
  procedure advance_generation(
    p_match in varchar2,p_membership_epoch in number,
    p_old_generation in number,p_new_generation in number);
  procedure materialize_temporal_bundle(
    p_match in varchar2,p_membership_epoch in number,
    p_generation in number,p_last_tic in number);
  procedure poll_latest(
    p_match in varchar2,p_player_slot in number,
    p_membership_epoch in number,p_generation in number,p_after_tic in number,
    p_ready out number,p_frame_tic out number,p_payload out blob);
  procedure poll_batch(
    p_match in varchar2,p_player_slot in number,
    p_membership_epoch in number,p_generation in number,p_after_tic in number,
    p_max_frames in number,p_frame_count out number,p_first_tic out number,
    p_last_tic out number,p_payload out blob);
end doom_mle_live_frame_transport;
/

create or replace package body doom_mle_live_frame_transport as
  c_error constant pls_integer := -20796;
  c_ring_entries constant pls_integer := 128;
  -- Level 1 is measurably faster end to end than raw 64 KiB DPB2 over the
  -- public ORDS path, despite sharing the single effective Free-tier CPU.
  c_compress_live_frames constant boolean := true;

  procedure initialize_ring(
    p_match in varchar2,p_players in number,
    p_membership_epoch in number,p_generation in number
  ) is
    l_members number;
  begin
    if p_players is null or p_players<>trunc(p_players)
       or p_players not between 1 and 4
       or p_membership_epoch is null or p_membership_epoch<1
       or p_generation is null or p_generation<1 then
      raise_application_error(c_error,'invalid live-frame ring fence');
    end if;
    select count(*) into l_members
      from doom_match_member
     where match_id=p_match
       and player_slot between 0 and p_players-1
       and membership_epoch=p_membership_epoch;
    if l_members<>p_players then
      raise_application_error(c_error,'live-frame membership mismatch');
    end if;
    delete from doom_match_live_frame where match_id=p_match;
    delete from doom_match_live_frame_batch where match_id=p_match;
    delete from doom_match_live_frame_views where match_id=p_match;
    for l_slot in 0..c_ring_entries-1 loop
      insert into doom_match_live_frame_views(
        match_id,ring_slot,membership_epoch,generation,tic,player_mask,
        payload_bytes,payload_blob,published_at)
      values(
        p_match,l_slot,p_membership_epoch,p_generation,-1,0,
        0,empty_blob(),null);
    end loop;
    for l_player in 0..p_players-1 loop
      for l_slot in 0..c_ring_entries-1 loop
        insert into doom_match_live_frame(
          match_id,player_slot,ring_slot,membership_epoch,generation,
          tic,palette_index,payload_bytes,payload_blob,published_at)
        values(
          p_match,l_player,l_slot,p_membership_epoch,p_generation,
          -1,0,0,empty_blob(),null);
        insert into doom_match_live_frame_batch(
          match_id,player_slot,ring_slot,membership_epoch,generation,
          first_tic,last_tic,frame_count,payload_bytes,payload_blob,published_at)
        values(
          p_match,l_player,l_slot,p_membership_epoch,p_generation,
          -1,-1,0,0,empty_blob(),null);
      end loop;
    end loop;
  end initialize_ring;

  procedure advance_generation(
    p_match in varchar2,p_membership_epoch in number,
    p_old_generation in number,p_new_generation in number
  ) is
  begin
    if p_new_generation<>p_old_generation+1 then
      raise_application_error(c_error,'live-frame recovery generation fence');
    end if;
    update doom_match_live_frame
       set generation=p_new_generation,tic=-1,palette_index=0,
           payload_bytes=0,published_at=null
     where match_id=p_match
       and membership_epoch=p_membership_epoch
       and generation=p_old_generation;
    if sql%rowcount=0 then
      raise_application_error(c_error,'live-frame recovery ring unavailable');
    end if;
    update doom_match_live_frame_batch
       set generation=p_new_generation,first_tic=-1,last_tic=-1,
           frame_count=0,payload_bytes=0,published_at=null
     where match_id=p_match
       and membership_epoch=p_membership_epoch
       and generation=p_old_generation;
    if sql%rowcount=0 then
      raise_application_error(
        c_error,'live-frame recovery batch ring unavailable');
    end if;
    update doom_match_live_frame_views
       set generation=p_new_generation,tic=-1,player_mask=0,
           payload_bytes=0,published_at=null
     where match_id=p_match
       and membership_epoch=p_membership_epoch
       and generation=p_old_generation;
    if sql%rowcount=0 then
      raise_application_error(
        c_error,'live-frame recovery shared-view ring unavailable');
    end if;
  end advance_generation;

  -- Convert one uncommitted EPT1 pair of exact MLE-rendered endpoints into a
  -- DPV2 interval-two through interval-five bundle. UTL_RAW performs the identical
  -- spatial phase mask in native database code; the authoritative
  -- uncompressed pixels never leave the database and the worker's surrounding
  -- transaction remains the only durability boundary. Single-POV masks 1
  -- and 2 allow multiplayer keyframes to be staggered without collapsing
  -- either authenticated viewpoint.
  procedure materialize_temporal_bundle(
    p_match in varchar2,p_membership_epoch in number,
    p_generation in number,p_last_tic in number
  ) is
    c_chunk_bytes constant pls_integer:=32766;
    type raw_table is table of raw(32767) index by pls_integer;
    l_current_mask raw_table;
    l_previous_mask raw_table;
    l_source blob;
    l_output blob;
    l_payload_bytes number;
    l_player_mask number;
    l_header raw(16);
    l_previous_meta raw(4);
    l_current_meta raw(4);
    l_previous_tic number;
    l_current_tic number;
    l_interval number;
    l_players number;
    l_frame_bytes number;
    l_endpoint_record_bytes number;
    l_previous_source number;
    l_current_source number;
    l_amount pls_integer;
    l_offset pls_integer;
    l_pattern pls_integer;
    l_previous_raw raw(32767);
    l_current_raw raw(32767);
    l_output_raw raw(32767);
    l_record raw(8);
    l_same_layout boolean;

    function phase_mask(
      p_numerator pls_integer,p_phase pls_integer,p_current boolean
    ) return raw is
      l_hex varchar2(10):='';
      l_pattern raw(5);
      l_mask raw(32767);
      l_copies pls_integer;
      l_remainder pls_integer;
      l_is_current boolean;
    begin
      for l_byte in 0..l_interval-1 loop
        l_is_current:=mod(p_phase+l_byte,l_interval)<p_numerator;
        if (l_is_current and p_current)
           or (not l_is_current and not p_current) then
          l_hex:=l_hex||'FF';
        else
          l_hex:=l_hex||'00';
        end if;
      end loop;
      l_pattern:=hextoraw(l_hex);
      l_copies:=floor(c_chunk_bytes/l_interval);
      l_remainder:=mod(c_chunk_bytes,l_interval);
      l_mask:=utl_raw.copies(l_pattern,l_copies);
      if l_remainder>0 then
        l_mask:=utl_raw.concat(
          l_mask,utl_raw.substr(l_pattern,1,l_remainder));
      end if;
      return l_mask;
    end phase_mask;

    procedure append_current_frame is
      l_copy_offset pls_integer:=1;
      l_copy_amount pls_integer;
    begin
      while l_copy_offset<=l_frame_bytes loop
        l_copy_amount:=least(
          c_chunk_bytes,l_frame_bytes-l_copy_offset+1);
        l_current_raw:=dbms_lob.substr(
          l_source,l_copy_amount,l_current_source+l_copy_offset-1);
        dbms_lob.writeappend(l_output,l_copy_amount,l_current_raw);
        l_copy_offset:=l_copy_offset+l_copy_amount;
      end loop;
    end append_current_frame;
  begin
    if p_match is null or not regexp_like(p_match,'^[0-9a-f]{32}$')
       or p_membership_epoch is null or p_membership_epoch<1
       or p_generation is null or p_generation<1
       or p_last_tic is null or p_last_tic<1
       or p_last_tic<>trunc(p_last_tic) then
      raise_application_error(c_error,'invalid EPT1 materialization fence');
    end if;
    select player_mask,payload_bytes,payload_blob
      into l_player_mask,l_payload_bytes,l_source
      from doom_match_live_frame_views
     where match_id=p_match
       and ring_slot=mod(p_last_tic,c_ring_entries)
       and membership_epoch=p_membership_epoch
       and generation=p_generation
       and tic=p_last_tic
     for update;
    l_header:=dbms_lob.substr(l_source,16,1);
    l_previous_tic:=to_number(rawtohex(
      utl_raw.substr(l_header,5,4)),'XXXXXXXX');
    l_current_tic:=to_number(rawtohex(
      utl_raw.substr(l_header,9,4)),'XXXXXXXX');
    l_interval:=to_number(rawtohex(
      utl_raw.substr(l_header,14,1)),'XX');
    if l_player_mask not in(1,2,3)
       or utl_raw.substr(l_header,1,4)<>hextoraw('45505431')
       or to_number(rawtohex(utl_raw.substr(l_header,13,1)),'XX')
            <>l_player_mask
       or l_interval not between 2 and 5
       or utl_raw.substr(l_header,15,2)<>hextoraw('0000')
       or l_current_tic<>p_last_tic
       or l_current_tic<>l_previous_tic+l_interval then
      raise_application_error(c_error,'persistent EPT1 header mismatch');
    end if;
    l_players:=case l_player_mask when 3 then 2 else 1 end;
    l_frame_bytes:=l_players*64000;
    l_endpoint_record_bytes:=4+l_frame_bytes;
    if l_payload_bytes<>16+2*l_endpoint_record_bytes
       or dbms_lob.getlength(l_source)<>l_payload_bytes then
      raise_application_error(c_error,'persistent EPT1 length mismatch');
    end if;
    l_previous_meta:=dbms_lob.substr(l_source,4,17);
    l_current_meta:=dbms_lob.substr(
      l_source,4,17+l_endpoint_record_bytes);
    if (l_player_mask in(1,3) and (
         to_number(rawtohex(utl_raw.substr(l_previous_meta,1,1)),'XX')
             not between 0 and 13
         or to_number(rawtohex(utl_raw.substr(l_current_meta,1,1)),'XX')
             not between 0 and 13))
       or (l_player_mask=3 and (
         to_number(rawtohex(utl_raw.substr(l_previous_meta,2,1)),'XX')
             not between 0 and 13
         or to_number(rawtohex(utl_raw.substr(l_current_meta,2,1)),'XX')
             not between 0 and 13))
       or (l_player_mask=1 and (
         utl_raw.substr(l_previous_meta,2,1)<>hextoraw('FF')
         or utl_raw.substr(l_current_meta,2,1)<>hextoraw('FF')))
       or (l_player_mask=2 and (
         utl_raw.substr(l_previous_meta,1,1)<>hextoraw('FF')
         or utl_raw.substr(l_current_meta,1,1)<>hextoraw('FF')
         or to_number(rawtohex(utl_raw.substr(l_previous_meta,2,1)),'XX')
              not between 0 and 13
         or to_number(rawtohex(utl_raw.substr(l_current_meta,2,1)),'XX')
              not between 0 and 13))
       or to_number(rawtohex(utl_raw.substr(l_previous_meta,3,1)),'XX')
            not in(0,1)
       or to_number(rawtohex(utl_raw.substr(l_current_meta,3,1)),'XX')
            not in(0,1)
       or utl_raw.substr(l_previous_meta,4,1)<>hextoraw('00')
       or utl_raw.substr(l_current_meta,4,1)<>hextoraw('00') then
      raise_application_error(c_error,'persistent EPT1 metadata mismatch');
    end if;
    l_previous_source:=21;
    l_current_source:=21+l_endpoint_record_bytes;
    l_same_layout:=utl_raw.compare(
      utl_raw.substr(l_previous_meta,3,2),
      utl_raw.substr(l_current_meta,3,2))=0;

    for l_numerator in 1..l_interval-1 loop
      for l_phase in 0..l_interval-1 loop
        l_pattern:=l_numerator*10+l_phase;
        l_current_mask(l_pattern):=
          phase_mask(l_numerator,l_phase,true);
        l_previous_mask(l_pattern):=
          phase_mask(l_numerator,l_phase,false);
      end loop;
    end loop;

    dbms_lob.createtemporary(l_output,true,dbms_lob.call);
    dbms_lob.writeappend(l_output,16,hextoraw(
      '44505632'||
      lpad(to_char(l_previous_tic+1,'FMXXXXXXXX'),8,'0')||
      lpad(to_char(l_interval,'FMXXXXXXXX'),8,'0')||
      lpad(to_char(l_player_mask,'FMXX'),2,'0')||'000000'));
    for l_numerator in 1..l_interval-1 loop
      l_record:=hextoraw(
        lpad(to_char(l_previous_tic+l_numerator,'FMXXXXXXXX'),8,'0')||
        rawtohex(case l_numerator
          when 1 then l_previous_meta else l_current_meta end));
      dbms_lob.writeappend(l_output,8,l_record);
      if not l_same_layout then
        append_current_frame;
      else
        l_offset:=1;
        while l_offset<=l_frame_bytes loop
          l_amount:=least(c_chunk_bytes,l_frame_bytes-l_offset+1);
          l_pattern:=l_numerator*10+
            mod((l_offset-1)+(l_previous_tic+l_numerator),l_interval);
          l_previous_raw:=dbms_lob.substr(
            l_source,l_amount,l_previous_source+l_offset-1);
          l_current_raw:=dbms_lob.substr(
            l_source,l_amount,l_current_source+l_offset-1);
          l_output_raw:=utl_raw.bit_or(
            utl_raw.bit_and(l_previous_raw,
              utl_raw.substr(l_previous_mask(l_pattern),1,l_amount)),
            utl_raw.bit_and(l_current_raw,
              utl_raw.substr(l_current_mask(l_pattern),1,l_amount)));
          dbms_lob.writeappend(l_output,l_amount,l_output_raw);
          l_offset:=l_offset+l_amount;
        end loop;
      end if;
    end loop;
    l_record:=hextoraw(
      lpad(to_char(l_current_tic,'FMXXXXXXXX'),8,'0')||
      rawtohex(l_current_meta));
    dbms_lob.writeappend(l_output,8,l_record);
    append_current_frame;
    if dbms_lob.getlength(l_output)
         <>16+l_interval*(8+l_frame_bytes) then
      raise_application_error(c_error,'materialized DPV2 length mismatch');
    end if;
    update doom_match_live_frame_views
       set payload_bytes=dbms_lob.getlength(l_output),
           payload_blob=l_output,published_at=systimestamp
     where match_id=p_match
       and ring_slot=mod(p_last_tic,c_ring_entries)
       and membership_epoch=p_membership_epoch
       and generation=p_generation
       and tic=p_last_tic;
    if sql%rowcount<>1 then
      raise_application_error(c_error,'EPT1 materialization row lost');
    end if;
    dbms_lob.freetemporary(l_output);
  exception
    when no_data_found then
      raise_application_error(c_error,'EPT1 materialization row unavailable');
    when others then
      if l_output is not null and dbms_lob.istemporary(l_output)=1 then
        dbms_lob.freetemporary(l_output);
      end if;
      raise;
  end materialize_temporal_bundle;

  procedure poll_latest(
    p_match in varchar2,p_player_slot in number,
    p_membership_epoch in number,p_generation in number,p_after_tic in number,
    p_ready out number,p_frame_tic out number,p_payload out blob
  ) is
    l_batch blob;
    l_count number;
    l_record_offset number;
    l_palette raw(1);
  begin
    p_ready:=0;p_frame_tic:=null;p_payload:=null;
    begin
      select last_tic,frame_count,payload_blob
        into p_frame_tic,l_count,l_batch
        from (
          select last_tic,frame_count,payload_blob
            from doom_match_live_frame_batch
           where match_id=p_match
             and player_slot=p_player_slot
             and membership_epoch=p_membership_epoch
             and generation=p_generation
             and last_tic>p_after_tic
             and frame_count between 1 and 6
           order by last_tic desc
        )
       where rownum=1;
      if dbms_lob.getlength(l_batch)<>8+l_count*64008 then
        raise_application_error(
          c_error,'live-frame latest batch length mismatch');
      end if;
      l_record_offset:=8+(l_count-1)*64008;
      l_palette:=dbms_lob.substr(l_batch,1,l_record_offset+5);
      if to_number(rawtohex(l_palette),'XX') not between 0 and 13 then
        raise_application_error(c_error,'live-frame latest palette mismatch');
      end if;
      dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
      dbms_lob.copy(p_payload,l_batch,64000,1,l_record_offset+9);
      p_ready:=1;
    exception when no_data_found then
      p_ready:=0;p_frame_tic:=null;p_payload:=null;
    end;
  end poll_latest;

  -- DPB2 is persisted directly by the compiled MLE renderer: four-byte magic,
  -- big-endian uint32 frame count, then repeated big-endian uint32 tic +
  -- palette byte + layout byte (0 column-major, 1 row-major) + two reserved
  -- zero bytes + one complete 64,000-byte indexed framebuffer. The normal
  -- path returns the persistent BLOB without
  -- PL/SQL frame assembly; only a suffix/bounded response needs a temporary.
  procedure poll_batch(
    p_match in varchar2,p_player_slot in number,
    p_membership_epoch in number,p_generation in number,p_after_tic in number,
    p_max_frames in number,p_frame_count out number,p_first_tic out number,
    p_last_tic out number,p_payload out blob
  ) is
    l_batch blob;
    l_batch_first number;
    l_batch_last number;
    l_batch_count number;
    l_skip number;
    l_available number;
    l_header raw(8);
    l_source_offset number;
    l_view_header raw(16);
    l_view_palette number;
    l_view_layout number;
    l_view_source_offset number;
    l_view_record_header raw(8);
    l_view_bundle blob;
    l_view_bundle_last number;
    l_view_bundle_mask number;
    l_view_bundle_bytes number;
    l_view_bundle_first number;
    l_view_bundle_count number;
    l_view_bundle_players number;
    l_view_bundle_record_bytes number;
    l_view_bundle_record_tic number;
    l_view_bundle_record_offset number;
    procedure encode_gzip_dpb2 is
      l_raw_payload blob:=p_payload;
      l_raw_bytes number;
    begin
      if l_raw_payload is null then return;end if;
      l_raw_bytes:=dbms_lob.getlength(l_raw_payload);
      p_payload:=utl_compress.lz_compress(l_raw_payload,1);
      if dbms_lob.getlength(p_payload)<18
         or dbms_lob.substr(p_payload,4,1)<>hextoraw('1F8B0800') then
        raise_application_error(c_error,'GZIP_DPB2_V1 encoding failed');
      end if;
      if dbms_lob.istemporary(l_raw_payload)=1 then
        dbms_lob.freetemporary(l_raw_payload);
      end if;
    end encode_gzip_dpb2;
  begin
    p_frame_count:=0;p_first_tic:=null;p_last_tic:=null;p_payload:=null;
    if p_max_frames is null or p_max_frames<>trunc(p_max_frames)
       or p_max_frames not between 1 and 8 then
      raise_application_error(c_error,'invalid live-frame batch bound');
    end if;
    -- DPV2 amortizes a complete temporal interval and both authenticated
    -- viewpoints through one persistent locator.  The BLOB never crosses
    -- the REST boundary intact: this definer-rights facade validates every
    -- record and extracts only the requesting member's POV into DPB2.
    -- Fill the caller's existing eight-frame contract from as many consecutive
    -- DPV2 locators as are already committed. A single-flight ORDS request
    -- must amortize a 50-170 ms network tail rather than returning at most one
    -- three-frame interval while confirmed frames wait in the ring.
    for l_bundle in (
      select tic,player_mask,payload_bytes,payload_blob
        from doom_match_live_frame_views
       where match_id=p_match
         and membership_epoch=p_membership_epoch
         and generation=p_generation
         and tic>p_after_tic
         and tic>(
           select coalesce(max(latest_.tic),-1)-64
             from doom_match_live_frame_views latest_
            where latest_.match_id=p_match
              and latest_.membership_epoch=p_membership_epoch
              and latest_.generation=p_generation
              and latest_.tic>=0)
         and bitand(player_mask,power(2,p_player_slot))<>0
         and dbms_lob.substr(payload_blob,4,1)=hextoraw('44505632')
       order by tic
    ) loop
      l_view_bundle_last:=l_bundle.tic;
      l_view_bundle_mask:=l_bundle.player_mask;
      l_view_bundle_bytes:=l_bundle.payload_bytes;
      l_view_bundle:=l_bundle.payload_blob;
      l_view_header:=dbms_lob.substr(l_view_bundle,16,1);
      l_view_bundle_first:=to_number(rawtohex(
        utl_raw.substr(l_view_header,5,4)),'XXXXXXXX');
      l_view_bundle_count:=to_number(rawtohex(
        utl_raw.substr(l_view_header,9,4)),'XXXXXXXX');
      if l_view_bundle_mask not in(1,2,3)
         or l_view_bundle_count not between 1 and 6
         or utl_raw.substr(l_view_header,1,4)<>hextoraw('44505632')
         or to_number(rawtohex(utl_raw.substr(l_view_header,13,1)),'XX')
              <>l_view_bundle_mask
         or utl_raw.substr(l_view_header,14,3)<>hextoraw('000000')
         or l_view_bundle_last
              <>l_view_bundle_first+l_view_bundle_count-1 then
        raise_application_error(c_error,'persistent DPV2 header mismatch');
      end if;
      l_view_bundle_players:=
        case l_view_bundle_mask when 3 then 2 else 1 end;
      l_view_bundle_record_bytes:=8+l_view_bundle_players*64000;
      if l_view_bundle_bytes
            <>16+l_view_bundle_count*l_view_bundle_record_bytes
         or dbms_lob.getlength(l_view_bundle)<>l_view_bundle_bytes then
        raise_application_error(c_error,'persistent DPV2 length mismatch');
      end if;
      for l_index in 0..l_view_bundle_count-1 loop
        l_view_bundle_record_offset:=
          17+l_index*l_view_bundle_record_bytes;
        l_view_record_header:=dbms_lob.substr(
          l_view_bundle,8,l_view_bundle_record_offset);
        l_view_bundle_record_tic:=to_number(rawtohex(
          utl_raw.substr(l_view_record_header,1,4)),'XXXXXXXX');
        if l_view_bundle_record_tic<>l_view_bundle_first+l_index
           or (l_view_bundle_mask in(1,3)
             and to_number(rawtohex(
               utl_raw.substr(l_view_record_header,5,1)),'XX')
                 not between 0 and 13)
           or (l_view_bundle_mask=3 and to_number(rawtohex(
                utl_raw.substr(l_view_record_header,6,1)),'XX')
                not between 0 and 13)
           or (l_view_bundle_mask=1
               and utl_raw.substr(l_view_record_header,6,1)
                 <>hextoraw('FF'))
           or (l_view_bundle_mask=2
               and utl_raw.substr(l_view_record_header,5,1)
                 <>hextoraw('FF'))
           or to_number(rawtohex(
                utl_raw.substr(l_view_record_header,7,1)),'XX')
                not in(0,1)
           or utl_raw.substr(l_view_record_header,8,1)<>hextoraw('00') then
          raise_application_error(c_error,'persistent DPV2 record mismatch');
        end if;
        if l_view_bundle_record_tic>p_after_tic
           and p_frame_count<p_max_frames then
          if p_frame_count>0
             and l_view_bundle_record_tic<>p_last_tic+1 then
            raise_application_error(
              c_error,'persistent DPV2 sequence mismatch');
          end if;
          l_view_palette:=to_number(rawtohex(utl_raw.substr(
            l_view_record_header,5+p_player_slot,1)),'XX');
          l_view_layout:=to_number(rawtohex(utl_raw.substr(
            l_view_record_header,7,1)),'XX');
          if p_frame_count=0 then
            dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
            dbms_lob.writeappend(
              p_payload,8,hextoraw('4450423200000000'));
            p_first_tic:=l_view_bundle_record_tic;
          end if;
          l_header:=hextoraw(
            lpad(to_char(l_view_bundle_record_tic,'FMXXXXXXXX'),8,'0')||
            lpad(to_char(l_view_palette,'FMXX'),2,'0')||
            lpad(to_char(l_view_layout,'FMXX'),2,'0')||'0000');
          dbms_lob.writeappend(p_payload,8,l_header);
          l_view_source_offset:=l_view_bundle_record_offset+8
            +case when l_view_bundle_mask=3
              then p_player_slot*64000 else 0 end;
          dbms_lob.copy(
            p_payload,l_view_bundle,64000,dbms_lob.getlength(p_payload)+1,
            l_view_source_offset);
          p_frame_count:=p_frame_count+1;
          p_last_tic:=l_view_bundle_record_tic;
        end if;
      end loop;
      exit when p_frame_count>=p_max_frames;
    end loop;
    if p_frame_count>0 then
      l_header:=hextoraw(
        '44504232'||lpad(to_char(p_frame_count,'FMXXXXXXXX'),8,'0'));
      dbms_lob.write(p_payload,8,1,l_header);
      if dbms_lob.getlength(p_payload)<>8+p_frame_count*64008 then
        raise_application_error(c_error,'assembled DPV2 batch mismatch');
      end if;
      if c_compress_live_frames then encode_gzip_dpb2; end if;
      return;
    end if;
    -- DPD1 is the immediate one-tic path: magic, tic, player mask, two
    -- palette bytes, layout byte, four reserved bytes, then complete frames
    -- in slot order.
    -- The worker still performs one locator write for both POVs. The read
    -- facade uses native LOB copy to return only the authenticated 64 KiB
    -- viewpoint, halving ORDS/Base64/network work versus shipping both views.
    for l_view in (
      select tic,player_mask,payload_bytes,payload_blob
        from (
          select tic,player_mask,payload_bytes,payload_blob
            from doom_match_live_frame_views
           where match_id=p_match
             and membership_epoch=p_membership_epoch
             and generation=p_generation
             and tic>p_after_tic
             -- Skipped render tics deliberately leave their physical modulo-64
             -- slots untouched. Once a reader falls behind, those slots can
             -- contain values from the preceding ring rotation and must not
             -- be interleaved with the current logical suffix. Restrict the
             -- response to the newest 64-tic window; the client receives a
             -- valid later FIRST_TIC and performs its existing confirmed
             -- ring-gap resync without a permanent ORA-20796 loop.
             and tic>(
               select coalesce(max(latest_.tic),-1)-64
                 from doom_match_live_frame_views latest_
                where latest_.match_id=p_match
                  and latest_.membership_epoch=p_membership_epoch
                  and latest_.generation=p_generation
                  and latest_.tic>=0)
             and bitand(player_mask,power(2,p_player_slot))<>0
             -- The preceding DPV2 lookup and this fallback are separate
             -- READ COMMITTED statements. A worker commit can become visible
             -- between them; never let that newly visible DPV2 row enter the
             -- legacy DPD1 validator and surface as an intermittent 555.
             and dbms_lob.substr(payload_blob,4,1)=hextoraw('44504431')
           order by tic
        )
       where rownum<=p_max_frames
    ) loop
      l_view_header:=dbms_lob.substr(l_view.payload_blob,16,1);
      if l_view.player_mask not in(1,2,3)
         or l_view.payload_bytes<>16+
           case l_view.player_mask when 3 then 128000 else 64000 end
         or dbms_lob.getlength(l_view.payload_blob)<>l_view.payload_bytes
         or utl_raw.substr(l_view_header,1,4)<>hextoraw('44504431')
         or to_number(rawtohex(utl_raw.substr(l_view_header,5,4)),
              'XXXXXXXX')<>l_view.tic
         or to_number(rawtohex(utl_raw.substr(l_view_header,9,1)),'XX')
              <>l_view.player_mask
         or to_number(rawtohex(utl_raw.substr(l_view_header,12,1)),'XX')
              not in(0,1)
         or utl_raw.substr(l_view_header,13,4)<>hextoraw('00000000')
         or (p_frame_count>0 and l_view.tic<>p_last_tic+1) then
        raise_application_error(c_error,'persistent DPD1 view mismatch');
      end if;
      l_view_palette:=to_number(rawtohex(
        utl_raw.substr(l_view_header,10+p_player_slot,1)),'XX');
      if l_view_palette not between 0 and 13 then
        raise_application_error(c_error,'persistent DPD1 palette mismatch');
      end if;
      l_view_layout:=to_number(rawtohex(
        utl_raw.substr(l_view_header,12,1)),'XX');
      if p_frame_count=0 then
        dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
        dbms_lob.writeappend(p_payload,8,hextoraw('4450423200000000'));
        p_first_tic:=l_view.tic;
      end if;
      l_view_record_header:=hextoraw(
        lpad(to_char(l_view.tic,'FMXXXXXXXX'),8,'0')||
        lpad(to_char(l_view_palette,'FMXX'),2,'0')||
        lpad(to_char(l_view_layout,'FMXX'),2,'0')||'0000');
      dbms_lob.writeappend(p_payload,8,l_view_record_header);
      l_view_source_offset:=
        17+case when l_view.player_mask=3
          then p_player_slot*64000 else 0 end;
      dbms_lob.copy(
        p_payload,l_view.payload_blob,64000,dbms_lob.getlength(p_payload)+1,
        l_view_source_offset);
      p_frame_count:=p_frame_count+1;
      p_last_tic:=l_view.tic;
    end loop;
    if p_frame_count>0 then
      l_header:=hextoraw(
        '44504232'||lpad(to_char(p_frame_count,'FMXXXXXXXX'),8,'0'));
      dbms_lob.write(p_payload,8,1,l_header);
      if dbms_lob.getlength(p_payload)<>8+p_frame_count*64008 then
        raise_application_error(c_error,'assembled DPD1 batch length mismatch');
      end if;
      if c_compress_live_frames then encode_gzip_dpb2; end if;
      return;
    end if;
    begin
      select first_tic,last_tic,frame_count,payload_blob
        into l_batch_first,l_batch_last,l_batch_count,l_batch
        from (
          select first_tic,last_tic,frame_count,payload_blob
            from doom_match_live_frame_batch
           where match_id=p_match
             and player_slot=p_player_slot
             and membership_epoch=p_membership_epoch
             and generation=p_generation
             and last_tic>p_after_tic
             and frame_count between 1 and 6
           order by first_tic
        )
       where rownum=1;
    exception when no_data_found then return;end;
    if l_batch_last<>l_batch_first+l_batch_count-1
       or dbms_lob.getlength(l_batch)<>8+l_batch_count*64008
       or dbms_lob.substr(l_batch,4,1)<>hextoraw('44504232')
       or to_number(rawtohex(dbms_lob.substr(l_batch,4,5)),'XXXXXXXX')
          <>l_batch_count then
      raise_application_error(c_error,'persistent DPB2 batch mismatch');
    end if;
    l_skip:=greatest(0,p_after_tic-l_batch_first+1);
    l_available:=l_batch_count-l_skip;
    if l_available<1 then
      raise_application_error(c_error,'persistent DPB2 frontier mismatch');
    end if;
    p_frame_count:=least(l_available,p_max_frames);
    p_first_tic:=l_batch_first+l_skip;
    p_last_tic:=p_first_tic+p_frame_count-1;
    if l_skip=0 and p_frame_count=l_batch_count then
      -- Zero-copy SQL path: return the worker's persistent MLE-authored DPB2.
      p_payload:=l_batch;
    else
      l_header:=hextoraw('44504232'||
        lpad(to_char(p_frame_count,'FMXXXXXXXX'),8,'0'));
      dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
      dbms_lob.writeappend(p_payload,8,l_header);
      l_source_offset:=9+l_skip*64008;
      dbms_lob.copy(
        p_payload,l_batch,p_frame_count*64008,9,l_source_offset);
    end if;
    if dbms_lob.getlength(p_payload)<>8+p_frame_count*64008 then
      raise_application_error(c_error,'live-frame batch length mismatch');
    end if;
    if c_compress_live_frames then encode_gzip_dpb2; end if;
  exception when others then
    if p_payload is not null and dbms_lob.istemporary(p_payload)=1 then
      dbms_lob.freetemporary(p_payload);
    end if;
    p_frame_count:=0;p_first_tic:=null;p_last_tic:=null;p_payload:=null;
    raise;
  end poll_batch;
end doom_mle_live_frame_transport;
/

commit;
