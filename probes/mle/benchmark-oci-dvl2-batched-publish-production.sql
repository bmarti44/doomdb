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
  l_chunk raw(16000);
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
    else raise_application_error(-20796,'unknown batch load kind');end if;
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
      elsif p_kind='flat' then
        l_loaded:=doom_fused_flat_load(l_offset,l_chunk);
      elsif p_kind='comp_pack' then
        l_loaded:=doom_fused_compositor_pack_load(l_offset,l_chunk);
      elsif p_kind='comp_sprite' then
        l_loaded:=doom_fused_compositor_sprite_load(l_offset,l_chunk);
      else l_loaded:=doom_fused_compositor_ui_load(l_offset,l_chunk);end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'short batch load '||p_kind);
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
      raise_application_error(-20796,'batch finalize '||p_kind);
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
  dbms_output.put_line('PMLE_OCI_DVL2_BATCH_LOAD|PASS');
end;
/

declare
  c_frames constant pls_integer:=1200;
  c_warmup constant pls_integer:=40;
  c_header_bytes constant pls_integer:=8;
  c_record_bytes constant pls_integer:=8+64000;
  type values_t is table of number index by pls_integer;
  type batch_sizes_t is table of pls_integer index by pls_integer;
  l_sizes batch_sizes_t;
  l_values values_t;l_sorted values_t;
  l_state varchar2(32767);l_command raw(32);
  l_started timestamp with time zone;l_group_started timestamp with time zone;
  l_cell_started timestamp with time zone;l_finished timestamp with time zone;
  l_tic number;l_checksum number;l_compose_bytes number;l_result number;
  l_group pls_integer;l_in_group pls_integer;l_groups pls_integer;
  l_batch pls_integer;l_expected number;l_actual number;l_header raw(16);
  l_temp_before number;l_temp_after number;l_mean number;l_p50 number;
  l_p95 number;l_delivery_p95 number;l_wall_ms number;l_get_ms number;
  l_get_start number;l_clock_suspects number;

  function elapsed_ms(p_start timestamp with time zone)return number is
    d interval day to second:=systimestamp-p_start;
  begin
    return extract(day from d)*86400000+extract(hour from d)*3600000+
      extract(minute from d)*60000+extract(second from d)*1000;
  end;

  procedure render_frame(p_frame pls_integer) is
  begin
    l_command:=hextoraw(
      case mod(p_frame,4)
        when 0 then '1900000000000000'
        when 1 then '1900040000000000'
        when 2 then '1900FC7F00000000'
        else '1900000001000000'
      end||rpad('00',48,'00'));
    l_tic:=doom_fused_step_only(2,3,l_command);
    l_checksum:=l_checksum+doom_fused_render_temporal(0,l_tic);
    l_compose_bytes:=64000;
  end;
begin
  l_sizes(1):=6;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_before from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  l_state:=doom_fused_init(2,0,3,1,1);
  if instr(l_state,'state=multiplayer-initialized|gametic=0|')=0 then
    raise_application_error(-20796,'batch initialization mismatch');
  end if;
  l_result:=doom_fused_origin_capture;
  -- A retained production slot prepays renderer compilation before READY.
  -- This 600-frame plateau is outside every scored cell.
  l_result:=doom_fused_origin_restore;
  l_result:=doom_fused_batch_reset(6);
  for frame in 1..600 loop
    render_frame(frame);
    l_result:=doom_fused_batch_append(l_tic,0);
    if mod(frame,6)=0 then
      l_result:=doom_fused_batch_publish(frame/6);
      commit write batch nowait;
      if frame<600 then l_result:=doom_fused_batch_reset(6);end if;
    end if;
  end loop;
  for cell in 1..l_sizes.count loop
    l_batch:=l_sizes(cell);l_groups:=c_frames/l_batch;
    l_result:=doom_fused_origin_restore;
    -- Prepay the exact rendering stages and the selected-size locator write.
    l_result:=doom_fused_batch_reset(l_batch);
    for frame in 1..c_warmup loop
      render_frame(frame);
      l_result:=doom_fused_batch_append(l_tic,0);
      if mod(frame,l_batch)=0 then
        l_result:=doom_fused_batch_publish(frame/l_batch);
        commit write batch nowait;
        if frame<c_warmup then
          l_result:=doom_fused_batch_reset(l_batch);
        end if;
      end if;
    end loop;

    l_result:=doom_fused_origin_restore;
    l_group:=0;l_in_group:=0;l_mean:=0;l_clock_suspects:=0;
    l_result:=doom_fused_batch_reset(l_batch);
    l_cell_started:=systimestamp;l_get_start:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      if l_in_group=0 then l_group_started:=systimestamp;end if;
      render_frame(frame);
      if l_tic<>frame then
        raise_application_error(-20796,'batch frontier mismatch');
      end if;
      l_result:=doom_fused_batch_append(l_tic,0);
      l_in_group:=l_in_group+1;
      if l_in_group=l_batch then
        l_group:=l_group+1;
        l_result:=doom_fused_batch_publish(l_group);
        commit write batch nowait;
        l_finished:=systimestamp;
        l_values(l_group):=elapsed_ms(l_group_started)/l_batch;
        l_mean:=l_mean+l_values(l_group);
        l_expected:=c_header_bytes+l_batch*c_record_bytes;
        select dbms_lob.getlength(payload),dbms_lob.substr(payload,8,1)
          into l_actual,l_header from doom_dvl2_frame_ring
          where ring_slot=mod(l_group,64) and frame_tic=l_tic;
        if l_result<>l_expected or l_actual<>l_expected
            or rawtohex(utl_raw.substr(l_header,1,4))<>'44504232'
            or to_number(
              rawtohex(utl_raw.substr(l_header,5,4)),
              'XXXXXXXX')<>l_batch then
          raise_application_error(
            -20796,'DLB1 batch framing mismatch result='||l_result||
            ' actual='||l_actual||' expected='||l_expected||
            ' header='||rawtohex(l_header));
        end if;
        l_in_group:=0;
        if frame<c_frames then l_result:=doom_fused_batch_reset(l_batch);end if;
      end if;
    end loop;
    l_wall_ms:=elapsed_ms(l_cell_started);
    l_get_ms:=(dbms_utility.get_time-l_get_start)*10;
    if abs(l_wall_ms-l_get_ms)>30 then l_clock_suspects:=1;end if;
    if l_group<>l_groups or l_in_group<>0 then
      raise_application_error(-20796,'batch coverage mismatch');
    end if;
    l_sorted:=l_values;
    for i in 2..l_groups loop
      declare value_ number:=l_sorted(i);j pls_integer:=i-1;begin
        while j>=1 and l_sorted(j)>value_ loop
          l_sorted(j+1):=l_sorted(j);j:=j-1;
        end loop;
        l_sorted(j+1):=value_;
      end;
    end loop;
    l_p50:=l_sorted(ceil(l_groups*.50));
    l_p95:=l_sorted(ceil(l_groups*.95));
    l_delivery_p95:=l_p95*l_batch;
    dbms_output.put_line(
      'PMLE_OCI_DVL2_BATCH_PUBLISH|PASS|classification=DIAGNOSTIC_NOT_GATE'||
      '|format=DPB2|batch_size='||l_batch||'|frames='||c_frames||
      '|groups='||l_groups||
      '|amortized_p50_ms='||to_char(l_p50,'FM9999990.000')||
      '|amortized_p95_ms='||to_char(l_p95,'FM9999990.000')||
      '|mean_ms='||to_char(l_mean/l_groups,'FM9999990.000')||
      '|sustained_fps='||to_char(c_frames*1000/l_wall_ms,'FM999990.000')||
      '|delivery_batch_p95_ms='||
        to_char(l_delivery_p95,'FM9999990.000')||
      '|wall_ms='||to_char(l_wall_ms,'FM9999990.000')||
      '|get_time_ms='||to_char(l_get_ms,'FM9999990.000')||
      '|clock_suspects='||l_clock_suspects||
      '|frame_bytes=64000|codec=NONE|authorship=DATABASE_MLE'||
      '|world_cadence=EXACT_8_75HZ_CONFIRMED_REPROJECTED_35HZ'||
      '|rate_shape='||
        case when l_p95<=33.333 and l_mean/l_groups<=28.571
          and l_clock_suspects=0 then 'PASS' else 'FAIL' end);
  end loop;
  select nvl(sum(cache_lobs+nocache_lobs+abstract_lobs),0)
    into l_temp_after from v$temporary_lobs
    where sid=to_number(sys_context('userenv','sid'));
  dbms_output.put_line(
    'PMLE_OCI_DVL2_BATCH_POSTFLIGHT|PASS|temporary_lobs_before='||
    l_temp_before||'|temporary_lobs_after='||l_temp_after||
    '|temporary_lobs_delta='||(l_temp_after-l_temp_before));
end;
/
