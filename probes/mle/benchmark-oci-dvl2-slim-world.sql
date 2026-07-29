whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

begin execute immediate 'drop table doom_dvl2_frame_ring purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
create table doom_dvl2_frame_ring(
  ring_slot number primary key,
  frame_tic number not null,
  payload blob not null,
  constraint doom_dvl2_frame_ring_slot_ck
    check(ring_slot between 0 and 63)
);
begin
  for slot_ in 0..63 loop
    insert into doom_dvl2_frame_ring values(slot_,-1,empty_blob());
  end loop;
  commit;
end;
/

declare
  l_blob blob;l_bytes number;l_offset number;l_loaded number;
  l_chunk raw(16000);l_state varchar2(32767);
  procedure load_bytes(p_kind varchar2,p_blob blob,p_bytes number) is
  begin
    l_offset:=0;
    if p_kind='iwad' then l_loaded:=doom_fused_allocate(p_bytes);
    elsif p_kind='table' then l_loaded:=doom_fused_table_allocate(p_bytes);
    elsif p_kind='pack' then l_loaded:=doom_fused_pack_allocate(p_bytes);
    elsif p_kind='wall' then l_loaded:=doom_fused_wall_allocate(p_bytes);
    elsif p_kind='flat' then l_loaded:=doom_fused_flat_allocate(p_bytes);
    elsif p_kind='comp_pack' then
      l_loaded:=doom_fused_compositor_pack_allocate(p_bytes);
    elsif p_kind='comp_sprite' then
      l_loaded:=doom_fused_compositor_sprite_allocate(p_bytes);
    elsif p_kind='comp_ui' then
      l_loaded:=doom_fused_compositor_ui_allocate(p_bytes);
    else raise_application_error(-20796,'unknown slim-world load kind');end if;
    while l_offset<p_bytes loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(16000,p_bytes-l_offset),l_offset+1);
      if p_kind='iwad' then l_loaded:=doom_fused_load(l_offset,l_chunk);
      elsif p_kind='table' then
        l_loaded:=doom_fused_table_load(l_offset,l_chunk);
      elsif p_kind='pack' then
        l_loaded:=doom_fused_pack_load(l_offset,l_chunk);
      elsif p_kind='wall' then
        l_loaded:=doom_fused_wall_load(l_offset,l_chunk);
      elsif p_kind='comp_pack' then
        l_loaded:=doom_fused_compositor_pack_load(l_offset,l_chunk);
      elsif p_kind='comp_sprite' then
        l_loaded:=doom_fused_compositor_sprite_load(l_offset,l_chunk);
      elsif p_kind='comp_ui' then
        l_loaded:=doom_fused_compositor_ui_load(l_offset,l_chunk);
      else l_loaded:=doom_fused_flat_load(l_offset,l_chunk);end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'short slim-world load '||p_kind);
      end if;
    end loop;
    if p_kind='pack' then l_loaded:=doom_fused_pack_finalize;
    elsif p_kind='wall' then l_loaded:=doom_fused_wall_finalize;
    elsif p_kind='flat' then l_loaded:=doom_fused_flat_finalize;
    elsif p_kind='comp_pack' then
      l_loaded:=doom_fused_compositor_pack_finalize;
    elsif p_kind='comp_sprite' then
      l_loaded:=doom_fused_compositor_sprite_finalize;
    elsif p_kind='comp_ui' then
      l_loaded:=doom_fused_compositor_ui_finalize;
    else return;end if;
    if l_loaded<>p_bytes then
      raise_application_error(-20796,'slim-world finalize '||p_kind);
    end if;
  end;
begin
  select payload_bytes into l_blob from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  load_bytes('iwad',l_blob,dbms_lob.getlength(l_blob));
  select table_pack_blob into l_blob from doom_dvl2_sim_source;
  load_bytes('table',l_blob,dbms_lob.getlength(l_blob));
  select pack_blob,pack_bytes into l_blob,l_bytes
    from doom_free_generated_source;load_bytes('pack',l_blob,l_bytes);
  select wall_blob,wall_bytes into l_blob,l_bytes
    from doom_free_generated_source;load_bytes('wall',l_blob,l_bytes);
  select flat_blob,flat_bytes into l_blob,l_bytes
    from doom_free_generated_source;load_bytes('flat',l_blob,l_bytes);
  select pack_blob,pack_bytes into l_blob,l_bytes
    from doom_free_compositor_source;
  load_bytes('comp_pack',l_blob,l_bytes);
  select sprite_blob,sprite_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_bytes('comp_sprite',l_blob,l_bytes);
  select ui_blob,ui_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_bytes('comp_ui',l_blob,l_bytes);
  l_state:=doom_fused_init(2,0,3,1,1);
  if instr(l_state,'state=multiplayer-initialized|gametic=0|')=0 then
    raise_application_error(-20796,'slim-world initialization mismatch');
  end if;
  dbms_output.put_line('PMLE_OCI_DVL2_SLIM_WORLD_LOAD|PASS');
end;
/

declare
  c_warm constant pls_integer:=300;
  c_frames constant pls_integer:=300;
  type values_t is table of number index by pls_integer;
  type hash_set_t is table of pls_integer index by varchar2(64);
  l_step values_t;l_snapshot values_t;l_import values_t;
  l_render values_t;l_compose_build values_t;l_compose_export values_t;
  l_compose_copy values_t;
  l_sprites values_t;
  l_weapon values_t;l_status values_t;l_publish values_t;l_total values_t;
  l_sorted values_t;
  l_started timestamp with time zone;l_a timestamp with time zone;
  l_b timestamp with time zone;l_c timestamp with time zone;
  l_d timestamp with time zone;l_d2 timestamp with time zone;
  l_e timestamp with time zone;
  l_f timestamp with time zone;l_g timestamp with time zone;
  l_h timestamp with time zone;l_i timestamp with time zone;
  l_k timestamp with time zone;
  l_command raw(32);
  l_tic number;l_checksum number;l_published number;l_unique number:=0;
  l_compose_bytes number;l_compose_min number:=32767;
  l_compose_max number:=0;
  l_j pls_integer;
  l_frame_hashes hash_set_t;l_ring_hashes hash_set_t;
  l_ring_full pls_integer:=0;
  l_ring_unique pls_integer:=0;l_hash varchar2(64);
  l_p95_threshold number;
  l_temp_lobs_before number:=0;l_temp_lobs_after number:=0;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
  procedure report(p_stage varchar2,p_values values_t) is
    l_value number;l_k pls_integer;l_mean number:=0;
  begin
    l_sorted:=p_values;
    for i in 2..c_frames loop
      l_value:=l_sorted(i);l_k:=i-1;
      while l_k>=1 and l_sorted(l_k)>l_value loop
        l_sorted(l_k+1):=l_sorted(l_k);l_k:=l_k-1;
      end loop;
      l_sorted(l_k+1):=l_value;
    end loop;
    for i in 1..c_frames loop l_mean:=l_mean+p_values(i);end loop;
    dbms_output.put_line(
      'PMLE_OCI_DVL2_SLIM_WORLD_STAGE|PASS|stage='||p_stage||
      '|p50_ms='||to_char(l_sorted(ceil(c_frames*.50)),'FM9999990.000')||
      '|p95_ms='||to_char(l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
      '|p99_ms='||to_char(l_sorted(ceil(c_frames*.99)),'FM9999990.000')||
      '|mean_ms='||to_char(l_mean/c_frames,'FM9999990.000'));
  end;
begin
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_lobs_before
    from v$temporary_lobs
   where sid=to_number(sys_context('userenv','sid'));
  -- Prepay renderer, compositor, locator, and commit first-touch work without
  -- advancing the simulation. The scored route must still begin at tic 1.
  for warm_ in 1..c_warm loop
    l_checksum:=doom_fused_stage_prepare(0);
    l_checksum:=l_checksum+doom_fused_stage_import;
    l_checksum:=l_checksum+doom_fused_stage_render;
    l_compose_bytes:=doom_fused_compose_build(0);
    l_checksum:=l_checksum+l_compose_bytes;
    l_checksum:=l_checksum+doom_fused_compose_export;
    l_checksum:=l_checksum+doom_fused_compose_copy;
    l_checksum:=l_checksum+doom_fused_compose_sprites;
    l_checksum:=l_checksum+doom_fused_compose_weapon;
    l_checksum:=l_checksum+doom_fused_compose_status;
    if doom_fused_publish_locator(0)<>64000 then
      raise_application_error(-20796,'renderer prewarm publication mismatch');
    end if;
    commit write batch nowait;
  end loop;
  for frame in 1..c_frames loop
    l_command:=hextoraw(
      case mod(frame,4)
        when 0 then '1900000000000000'
        when 1 then '1900040000000000'
        when 2 then '1900FC7F00000000'
        else '1900000001000000'
      end||rpad('00',48,'00'));
    l_started:=systimestamp;
    l_tic:=doom_fused_step_only(2,3,l_command);
    l_a:=systimestamp;
    l_checksum:=doom_fused_stage_prepare(0);
    l_b:=systimestamp;
    l_checksum:=l_checksum+doom_fused_stage_import;
    l_c:=systimestamp;
    l_checksum:=l_checksum+doom_fused_stage_render;
    l_d:=systimestamp;
    l_compose_bytes:=doom_fused_compose_build(0);
    l_checksum:=l_checksum+l_compose_bytes;
    l_d2:=systimestamp;
    l_checksum:=l_checksum+doom_fused_compose_export;
    l_e:=systimestamp;
    l_checksum:=l_checksum+doom_fused_compose_copy;
    l_f:=systimestamp;
    l_checksum:=l_checksum+doom_fused_compose_sprites;
    l_g:=systimestamp;
    l_checksum:=l_checksum+doom_fused_compose_weapon;
    l_h:=systimestamp;
    l_checksum:=l_checksum+doom_fused_compose_status;
    l_i:=systimestamp;
    l_published:=doom_fused_publish_locator(l_tic);
    commit write batch nowait;
    l_k:=systimestamp;
    if l_tic<>frame or l_published<>64000 then
      raise_application_error(-20796,'slim-world pipeline contract');
    end if;
    l_j:=frame;
      l_step(l_j):=elapsed_ms(l_a-l_started);
      l_snapshot(l_j):=elapsed_ms(l_b-l_a);
      l_import(l_j):=elapsed_ms(l_c-l_b);
      l_render(l_j):=elapsed_ms(l_d-l_c);
      l_compose_build(l_j):=elapsed_ms(l_d2-l_d);
      l_compose_export(l_j):=elapsed_ms(l_e-l_d2);
      l_compose_copy(l_j):=elapsed_ms(l_f-l_e);
      l_sprites(l_j):=elapsed_ms(l_g-l_f);
      l_weapon(l_j):=elapsed_ms(l_h-l_g);
      l_status(l_j):=elapsed_ms(l_i-l_h);
      l_publish(l_j):=elapsed_ms(l_k-l_i);
      l_total(l_j):=elapsed_ms(l_k-l_started);
      l_compose_min:=least(l_compose_min,l_compose_bytes);
      l_compose_max:=greatest(l_compose_max,l_compose_bytes);
      -- Identity evidence is deliberately outside the timed pipeline.  Hash
      -- the just-published BLOB so every scored frame, not merely the final
      -- 64-slot ring contents, participates in the uniqueness gate.
      select lower(rawtohex(
        dbms_crypto.hash(payload,dbms_crypto.hash_sh256)))
        into l_hash from doom_dvl2_frame_ring
        where ring_slot=mod(l_tic,64) and frame_tic=l_tic;
    if not l_frame_hashes.exists(l_hash) then
      l_frame_hashes(l_hash):=1;l_unique:=l_unique+1;
    end if;
  end loop;
  for frame_ in (select payload from doom_dvl2_frame_ring) loop
    if dbms_lob.getlength(frame_.payload)=64000 then
      l_ring_full:=l_ring_full+1;
    end if;
    l_hash:=lower(rawtohex(
      dbms_crypto.hash(frame_.payload,dbms_crypto.hash_sh256)));
    if not l_ring_hashes.exists(l_hash) then
      l_ring_hashes(l_hash):=1;l_ring_unique:=l_ring_unique+1;
    end if;
  end loop;
  if l_ring_full<>64 or l_ring_unique<>64 then
    raise_application_error(-20796,'slim-world ring identity mismatch');
  end if;
  if doom_fused_native_view_verify<>3 then
    raise_application_error(-20796,'native view contract mismatch');
  end if;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_lobs_after
    from v$temporary_lobs
   where sid=to_number(sys_context('userenv','sid'));
  if l_temp_lobs_after-l_temp_lobs_before>2 then
    raise_application_error(
      -20796,'persistent locator temporary LOB growth is unbounded');
  end if;
  report('AUTHORITY_STEP',l_step);
  report('DVL2_SNAPSHOT_BUILD',l_snapshot);
  report('DVL2_DYNAMIC_IMPORT',l_import);
  report('COARSE_WORLD_RASTER',l_render);
  report('COMPOSITOR_SNAPSHOT_BUILD',l_compose_build);
  report('COMPOSITOR_SNAPSHOT_EXPORT',l_compose_export);
  report('COMPOSITOR_BUFFER_COPY',l_compose_copy);
  report('WORLD_SPRITES',l_sprites);
  report('WEAPON_PSPRITES',l_weapon);
  report('STATUS_BAR_HUD',l_status);
  report('BLOB_RING_PUBLISH',l_publish);
  report('TOTAL',l_total);
  l_sorted:=l_total;
  for i in 2..c_frames loop
    declare l_value number:=l_sorted(i);l_k pls_integer:=i-1;begin
      while l_k>=1 and l_sorted(l_k)>l_value loop
        l_sorted(l_k+1):=l_sorted(l_k);l_k:=l_k-1;end loop;
      l_sorted(l_k+1):=l_value;end;
  end loop;
  l_p95_threshold:=l_sorted(ceil(c_frames*.95));
  for frame in 1..c_frames loop
    if l_total(frame)>=l_p95_threshold then
      dbms_output.put_line(
        'PMLE_OCI_DVL2_TAIL|PASS|frame='||frame||
        '|total_ms='||to_char(l_total(frame),'FM9999990.000')||
        '|authority_ms='||to_char(l_step(frame),'FM9999990.000')||
        '|raster_ms='||to_char(l_render(frame),'FM9999990.000')||
        '|snapshot_build_ms='||
          to_char(l_compose_build(frame),'FM9999990.000')||
        '|sprites_ms='||to_char(l_sprites(frame),'FM9999990.000')||
        '|weapon_ms='||to_char(l_weapon(frame),'FM9999990.000')||
        '|hud_ms='||to_char(l_status(frame),'FM9999990.000')||
        '|publish_ms='||to_char(l_publish(frame),'FM9999990.000'));
    end if;
  end loop;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_SLIM_WORLD|PASS|frames='||c_frames||
    '|unique='||l_unique||'|ring_full='||l_ring_full||
    '|ring_unique='||l_ring_unique||
    '|native_views=3'||
    '|transport=persistent_returning_oracle_blob'||
    '|temporary_lobs_before='||l_temp_lobs_before||
    '|temporary_lobs_after='||l_temp_lobs_after||
    '|temporary_lobs_delta='||(l_temp_lobs_after-l_temp_lobs_before)||
    '|compositor_bytes_min='||l_compose_min||
    '|compositor_bytes_max='||l_compose_max||
    '|p95_ms='||to_char(l_p95_threshold,'FM9999990.000')||
    '|fps_p95='||
      to_char(1000/l_p95_threshold,'FM9999990.000')||
    '|gate='||case when l_p95_threshold<=33.333
      and l_unique=c_frames and l_ring_unique=64
      then 'PASS' else 'FAIL' end);
  doom_fused_release;
exception when others then
  begin doom_fused_release;exception when others then null;end;raise;
end;
/
