whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

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
    elsif p_kind='sprite' then l_loaded:=doom_fused_sprite_allocate(p_bytes);
    elsif p_kind='ui' then l_loaded:=doom_fused_ui_allocate(p_bytes);
    else raise_application_error(-20796,'unknown fused load kind');end if;
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
      elsif p_kind='sprite' then
        l_loaded:=doom_fused_sprite_load(l_offset,l_chunk);
      else l_loaded:=doom_fused_ui_load(l_offset,l_chunk);end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'short fused load '||p_kind);
      end if;
    end loop;
    if p_kind='pack' then l_loaded:=doom_fused_pack_finalize;
    elsif p_kind='wall' then l_loaded:=doom_fused_wall_finalize;
    elsif p_kind='flat' then l_loaded:=doom_fused_flat_finalize;
    elsif p_kind='sprite' then l_loaded:=doom_fused_sprite_finalize;
    elsif p_kind='ui' then l_loaded:=doom_fused_ui_finalize;
    else return;end if;
    if l_loaded<>p_bytes then
      raise_application_error(-20796,'fused finalize mismatch '||p_kind);
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
  select sprite_blob,sprite_bytes into l_blob,l_bytes
    from doom_free_generated_source;load_bytes('sprite',l_blob,l_bytes);
  select ui_blob,ui_bytes into l_blob,l_bytes
    from doom_free_generated_source;load_bytes('ui',l_blob,l_bytes);
  l_state:=doom_fused_init(2,0,3,1,1);
  if instr(l_state,'state=multiplayer-initialized|gametic=0|')=0 then
    raise_application_error(-20796,'fused initialization mismatch');
  end if;
  dbms_output.put_line('PMLE_OCI_DVL2_FUSED_LOAD|PASS');
end;
/
declare
  c_warm constant pls_integer:=40;c_frames constant pls_integer:=300;
  type values_t is table of number index by pls_integer;
  l_pipeline values_t;l_egress values_t;l_total values_t;l_sorted values_t;
  l_started timestamp with time zone;l_a timestamp with time zone;
  l_b timestamp with time zone;l_command raw(32);l_one raw(32000);
  l_two raw(32000);l_previous raw(32000);l_tic number;l_unique number:=0;
  l_j pls_integer;
  function elapsed_ms(p interval day to second)return number is begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;end;
  procedure report(p_name varchar2,p_values values_t) is
    l_value number;l_k pls_integer;l_mean number:=0;
  begin
    l_sorted:=p_values;
    for i in 2..c_frames loop
      l_value:=l_sorted(i);l_k:=i-1;
      while l_k>=1 and l_sorted(l_k)>l_value loop
        l_sorted(l_k+1):=l_sorted(l_k);l_k:=l_k-1;end loop;
      l_sorted(l_k+1):=l_value;end loop;
    for i in 1..c_frames loop l_mean:=l_mean+p_values(i);end loop;
    dbms_output.put_line(
      'PMLE_OCI_DVL2_FUSED_STAGE|PASS|stage='||p_name||
      '|p50_ms='||to_char(l_sorted(ceil(c_frames*.5)),'FM9999990.000')||
      '|p95_ms='||to_char(l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
      '|mean_ms='||to_char(l_mean/c_frames,'FM9999990.000'));
  end;
begin
  for frame in 1..c_warm+c_frames loop
    l_command:=hextoraw(
      case mod(frame,4)
        when 0 then '1900000000000000'
        when 1 then '1900040000000000'
        when 2 then '1900FC7F00000000'
        else '1900000001000000'
      end||rpad('00',48,'00'));
    l_started:=systimestamp;
    l_tic:=doom_fused_step_render(2,3,l_command,0);
    l_a:=systimestamp;
    l_one:=doom_fused_frame_chunk(0,32000);
    l_two:=doom_fused_frame_chunk(32000,32000);
    l_b:=systimestamp;
    if l_tic<>frame or utl_raw.length(l_one)<>32000
       or utl_raw.length(l_two)<>32000 then
      raise_application_error(-20796,'fused frame contract mismatch');
    end if;
    if frame>c_warm and (l_previous is null or l_one<>l_previous)
    then l_unique:=l_unique+1;end if;
    l_previous:=l_one;
    if frame>c_warm then
      l_j:=frame-c_warm;
      l_pipeline(l_j):=elapsed_ms(l_a-l_started);
      l_egress(l_j):=elapsed_ms(l_b-l_a);
      l_total(l_j):=elapsed_ms(l_b-l_started);
    end if;
  end loop;
  report('FUSED_STEP_SNAPSHOT_RENDER',l_pipeline);
  report('RAW64K_EGRESS',l_egress);
  report('TOTAL',l_total);
  l_sorted:=l_total;
  for i in 2..c_frames loop
    declare l_value number:=l_sorted(i);l_k pls_integer:=i-1;begin
      while l_k>=1 and l_sorted(l_k)>l_value loop
        l_sorted(l_k+1):=l_sorted(l_k);l_k:=l_k-1;end loop;
      l_sorted(l_k+1):=l_value;end;end loop;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_FUSED_FRAME|PASS|frames='||c_frames||
    '|unique='||l_unique||
    '|p95_ms='||to_char(l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
    '|fps_p95='||
      to_char(1000/l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
    '|gate='||case when l_sorted(ceil(c_frames*.95))<=33.333 and
                           l_unique=c_frames then 'PASS' else 'FAIL' end);
  doom_fused_release;
exception when others then
  begin doom_fused_release;exception when others then null;end;raise;
end;
/
