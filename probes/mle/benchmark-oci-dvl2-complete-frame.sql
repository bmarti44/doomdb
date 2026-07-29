whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  l_blob blob;l_bytes number;l_iwad_bytes number;l_offset number;l_loaded number;
  l_chunk raw(16000);l_state varchar2(32767);
begin
  select payload_bytes into l_blob from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  l_bytes:=dbms_lob.getlength(l_blob);
  l_iwad_bytes:=l_bytes;
  l_loaded:=doom_dvl2_sim_allocate(l_bytes);
  l_offset:=0;
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_dvl2_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'DVL2 IWAD short load');
    end if;
  end loop;
  select table_pack_blob into l_blob from doom_dvl2_sim_source;
  l_bytes:=dbms_lob.getlength(l_blob);
  l_loaded:=doom_dvl2_sim_table_allocate(l_bytes);
  l_offset:=0;
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_dvl2_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'DVL2 table short load');
    end if;
  end loop;
  l_state:=doom_dvl2_sim_multi_init_game(2,0,3,1,1);
  if instr(l_state,'state=multiplayer-initialized|gametic=0|')=0 then
    raise_application_error(-20796,'DVL2 authority initialization');
  end if;
  dbms_output.put_line(
    'PMLE_DVL2_AUTHORITY_LOAD|PASS|iwad_bytes='||l_iwad_bytes||
    '|table_bytes='||l_bytes);
end;
/

declare
  l_blob blob;l_bytes number;l_offset number;l_loaded number;
  l_chunk raw(16000);
  procedure load_blob(
    p_kind varchar2,p_blob blob,p_bytes number
  ) is
  begin
    l_offset:=0;
    if p_kind='pack' then l_loaded:=doom_free_gen_allocate(p_bytes);
    elsif p_kind='wall' then l_loaded:=doom_free_gen_texture_allocate(p_bytes);
    elsif p_kind='flat' then l_loaded:=doom_free_gen_flat_allocate(p_bytes);
    elsif p_kind='sprite' then l_loaded:=doom_free_gen_sprite_allocate(p_bytes);
    elsif p_kind='ui' then l_loaded:=doom_free_gen_ui_allocate(p_bytes);
    else raise_application_error(-20796,'unknown renderer asset kind');
    end if;
    while l_offset<p_bytes loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(16000,p_bytes-l_offset),l_offset+1);
      if p_kind='pack' then
        l_loaded:=doom_free_gen_load(l_offset,l_chunk);
      elsif p_kind='wall' then
        l_loaded:=doom_free_gen_texture_load(l_offset,l_chunk);
      elsif p_kind='flat' then
        l_loaded:=doom_free_gen_flat_load(l_offset,l_chunk);
      elsif p_kind='sprite' then
        l_loaded:=doom_free_gen_sprite_load(l_offset,l_chunk);
      else l_loaded:=doom_free_gen_ui_load(l_offset,l_chunk);
      end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'renderer asset short load '||p_kind);
      end if;
    end loop;
    if p_kind='pack' then l_loaded:=doom_free_gen_finalize;
    elsif p_kind='wall' then l_loaded:=doom_free_gen_texture_finalize;
    elsif p_kind='flat' then l_loaded:=doom_free_gen_flat_finalize;
    elsif p_kind='sprite' then l_loaded:=doom_free_gen_sprite_finalize;
    else l_loaded:=doom_free_gen_ui_finalize;
    end if;
    if l_loaded<>p_bytes then
      raise_application_error(-20796,'renderer asset finalize '||p_kind);
    end if;
  end;
begin
  select pack_blob,pack_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_blob('pack',l_blob,l_bytes);
  select wall_blob,wall_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_blob('wall',l_blob,l_bytes);
  select flat_blob,flat_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_blob('flat',l_blob,l_bytes);
  select sprite_blob,sprite_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_blob('sprite',l_blob,l_bytes);
  select ui_blob,ui_bytes into l_blob,l_bytes
    from doom_free_generated_source;
  load_blob('ui',l_blob,l_bytes);
  dbms_output.put_line('PMLE_DVL2_RENDERER_LOAD|PASS');
end;
/

declare
  c_warm constant pls_integer:=40;
  c_frames constant pls_integer:=300;
  type values_t is table of number index by pls_integer;
  l_step values_t;l_snapshot values_t;l_render values_t;l_egress values_t;
  l_dynamic_import values_t;l_geometry values_t;
  l_world_sprites values_t;l_weapon values_t;
  l_status values_t;
  l_total values_t;l_sorted values_t;
  l_started timestamp with time zone;l_a timestamp with time zone;
  l_b timestamp with time zone;l_c timestamp with time zone;
  l_c2 timestamp with time zone;l_c3 timestamp with time zone;
  l_c4 timestamp with time zone;l_d timestamp with time zone;
  l_e timestamp with time zone;
  l_command raw(32);l_world raw(32767);l_frame1 raw(32000);
  l_frame2 raw(32000);l_previous1 raw(32000);l_previous2 raw(32000);
  l_length number;l_tic number;l_checksum number:=0;l_unique number:=0;
  l_j pls_integer;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
  procedure sort_values(p_values values_t,p_sorted out values_t) is
    l_value number;l_k pls_integer;
  begin
    p_sorted:=p_values;
    for i in 2..c_frames loop
      l_value:=p_sorted(i);l_k:=i-1;
      while l_k>=1 and p_sorted(l_k)>l_value loop
        p_sorted(l_k+1):=p_sorted(l_k);l_k:=l_k-1;
      end loop;
      p_sorted(l_k+1):=l_value;
    end loop;
  end;
  procedure report_stage(p_stage varchar2,p_values values_t) is
    l_mean number:=0;
  begin
    sort_values(p_values,l_sorted);
    for i in 1..c_frames loop l_mean:=l_mean+p_values(i);end loop;
    dbms_output.put_line(
      'PMLE_OCI_DVL2_COMPLETE_STAGE|PASS|stage='||p_stage||
      '|frames='||c_frames||
      '|p50_ms='||to_char(l_sorted(ceil(c_frames*.50)),'FM9999990.000')||
      '|p95_ms='||to_char(l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
      '|p99_ms='||to_char(l_sorted(ceil(c_frames*.99)),'FM9999990.000')||
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
    l_tic:=doom_dvl2_sim_authority_step(2,3,l_command);
    l_a:=systimestamp;
    l_length:=doom_dvl2_sim_world_length(0);
    if l_length<208 or l_length>32767 then
      raise_application_error(-20796,'invalid DVL2 world length');
    end if;
    l_world:=doom_dvl2_sim_world_chunk(0,l_length);
    l_b:=systimestamp;
    l_checksum:=l_checksum+doom_free_gen_load_dynamics(l_world);
    l_c:=systimestamp;
    l_checksum:=l_checksum+doom_free_gen_loaded_geometry(l_world);
    l_c2:=systimestamp;
    l_checksum:=l_checksum+doom_free_gen_world_sprites(l_world);
    l_c3:=systimestamp;
    l_checksum:=l_checksum+doom_free_gen_weapon(l_world);
    l_c4:=systimestamp;
    l_checksum:=l_checksum+doom_free_gen_status(l_world);
    l_e:=systimestamp;
    l_frame1:=doom_free_gen_frame_chunk(0,32000);
    l_frame2:=doom_free_gen_frame_chunk(32000,32000);
    l_d:=systimestamp;
    if utl_raw.length(l_frame1)<>32000 or
       utl_raw.length(l_frame2)<>32000 then
      raise_application_error(-20796,'short complete frame egress');
    end if;
    if frame>c_warm and
       (l_previous1 is null or l_frame1<>l_previous1 or
        l_frame2<>l_previous2)
    then l_unique:=l_unique+1;end if;
    l_previous1:=l_frame1;l_previous2:=l_frame2;
    if frame>c_warm then
      l_j:=frame-c_warm;
      l_step(l_j):=elapsed_ms(l_a-l_started);
      l_snapshot(l_j):=elapsed_ms(l_b-l_a);
      l_dynamic_import(l_j):=elapsed_ms(l_c-l_b);
      l_geometry(l_j):=elapsed_ms(l_c2-l_c);
      l_world_sprites(l_j):=elapsed_ms(l_c3-l_c2);
      l_weapon(l_j):=elapsed_ms(l_c4-l_c3);
      l_status(l_j):=elapsed_ms(l_e-l_c4);
      l_render(l_j):=elapsed_ms(l_e-l_b);
      l_egress(l_j):=elapsed_ms(l_d-l_e);
      l_total(l_j):=elapsed_ms(l_d-l_started);
    end if;
  end loop;
  report_stage('AUTHORITY_STEP',l_step);
  report_stage('DVL2_SNAPSHOT',l_snapshot);
  report_stage('DYNAMIC_IMPORT',l_dynamic_import);
  report_stage('GEOMETRY',l_geometry);
  report_stage('WORLD_SPRITES',l_world_sprites);
  report_stage('WEAPON_PSPRITES',l_weapon);
  report_stage('STATUS_BAR',l_status);
  report_stage('COMPLETE_RASTER',l_render);
  report_stage('RAW64K_EGRESS',l_egress);
  report_stage('TOTAL',l_total);
  sort_values(l_total,l_sorted);
  dbms_output.put_line(
    'PMLE_OCI_DVL2_COMPLETE_FRAME|PASS|frames='||c_frames||
    '|warmup='||c_warm||'|unique='||l_unique||
    '|total_p95_ms='||
      to_char(l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
    '|fps_p95='||
      to_char(1000/l_sorted(ceil(c_frames*.95)),'FM9999990.000')||
    '|budget_ms=33.333|gate='||
      case when l_sorted(ceil(c_frames*.95))<=33.333 and
                     l_unique>=c_frames
           then 'PASS' else 'FAIL' end||
    '|authority=MOCHA_TEAVM|renderer=COMPLETE_SPECIALIZED_TEAVM_MLE'||
    '|client=PIXEL_COPY_ONLY|world_format=DVL2|checksum='||l_checksum);
  doom_dvl2_sim_release;
exception when others then
  begin doom_dvl2_sim_release;exception when others then null;end;
  raise;
end;
/
