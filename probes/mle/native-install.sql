whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin
  execute immediate 'drop package doom_mle_native_bench';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/

create or replace package doom_mle_native_bench authid definer as
  procedure render_translated_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
  procedure render_gathered_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
  procedure render_hex_block_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
  procedure render_buffered_frame(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
  procedure render_command_stream(
    p_commands in raw,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
  procedure reset_draw_calls;
  procedure consume_draw_call(
    p_kind in pls_integer,
    p0 in pls_integer,
    p1 in pls_integer,
    p2 in pls_integer,
    p3 in pls_integer,
    p4 in pls_integer,
    p5 in pls_integer,
    p6 in pls_integer);
  procedure read_draw_checksum(p_checksum out pls_integer);
  procedure consume_draw_batch(p_commands in raw);
  procedure consume_draw_blob(p_commands in blob);
  procedure finish_draw_frame(
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer);
end doom_mle_native_bench;
/

create or replace package body doom_mle_native_bench as
  c_width constant pls_integer := 320;
  c_height constant pls_integer := 200;
  type raw_table is table of raw(32767) index by pls_integer;
  type int_table is table of simple_integer index by pls_integer;
  type text_table is table of varchar2(2) index by pls_integer;
  g_columns raw_table;
  g_maps raw_table;
  g_texture int_table;
  g_colormaps int_table;
  g_hex text_table;
  g_bytes raw_table;
  g_frame int_table;
  g_from_set raw(256);
  g_ready boolean := false;
  g_draw_checksum simple_integer := 0;

  procedure initialize is
    l_hex varchar2(32767);
    l_value simple_integer := 0;
  begin
    if g_ready then return; end if;
    l_hex := null;
    for value_ in 0..255 loop
      g_hex(value_) := to_char(value_, 'FM0X');
      g_bytes(value_) := hextoraw(g_hex(value_));
      l_hex := l_hex || g_hex(value_);
    end loop;
    g_from_set := hextoraw(l_hex);

    for i in 0..4095 loop
      g_texture(i) := mod(i * 73 + trunc(i / 8) + 19, 256);
    end loop;
    for light_ in 0..31 loop
      l_hex := null;
      for color_ in 0..255 loop
        l_value := greatest(0, color_ - light_ * 3);
        g_colormaps(light_ * 256 + color_) := l_value;
        l_hex := l_hex || g_hex(l_value);
      end loop;
      g_maps(light_) := hextoraw(l_hex);
    end loop;
    for column_ in 0..255 loop
      l_hex := null;
      for y_ in 0..c_height - 1 loop
        l_value := g_texture(mod(column_ * 11 + (y_ + 1) * 3, 64) * 64 +
          mod(column_, 64));
        l_hex := l_hex || g_hex(l_value);
      end loop;
      g_columns(column_) := hextoraw(l_hex);
    end loop;
    for pixel_ in 0..c_width * c_height - 1 loop g_frame(pixel_) := 0; end loop;
    g_ready := true;
  end initialize;

  procedure render_translated_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_column raw(200);
  begin
    initialize;
    p_chunk0 := null;
    p_chunk1 := null;
    p_checksum := 0;
    for x_ in 0..c_width - 1 loop
      l_column := utl_raw.translate(
        g_columns(mod(x_ + p_seed, 256)),
        g_maps(mod(trunc((x_ + p_seed) / 8), 32)),
        g_from_set);
      if x_ < 160 then
        p_chunk0 := utl_raw.concat(p_chunk0, l_column);
      else
        p_chunk1 := utl_raw.concat(p_chunk1, l_column);
      end if;
      p_checksum := p_checksum + to_number(rawtohex(utl_raw.substr(l_column, 1, 1)), 'XX');
    end loop;
  end render_translated_columns;

  procedure render_gathered_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_hex varchar2(400);
    l_column raw(200);
    l_ray number;
    l_light_base simple_integer := 0;
    l_texture_x simple_integer := 0;
    l_texture_y simple_integer := 0;
    l_step simple_integer := 0;
    l_pixel simple_integer := 0;
  begin
    initialize;
    p_chunk0 := null;
    p_chunk1 := null;
    p_checksum := 0;
    for x_ in 0..c_width - 1 loop
      l_ray := x_ + p_seed;
      l_ray := mod(l_ray * 1103515245 + 12345, 2147483648);
      l_light_base := mod(trunc(l_ray / 524288) + trunc(x_ / 16), 32) * 256;
      l_texture_x := mod(trunc(l_ray / 128), 64);
      l_texture_y := mod(p_seed + x_ * 3, 64);
      l_step := mod(trunc(l_ray / 8388608), 8) + 1;
      l_hex := null;
      for y_ in 0..c_height - 1 loop
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_hex := l_hex || g_hex(l_pixel);
      end loop;
      l_column := hextoraw(l_hex);
      if x_ < 160 then
        p_chunk0 := utl_raw.concat(p_chunk0, l_column);
      else
        p_chunk1 := utl_raw.concat(p_chunk1, l_column);
      end if;
      p_checksum := p_checksum + to_number(substr(l_hex, 1, 2), 'XX');
    end loop;
  end render_gathered_columns;

  procedure render_hex_block_columns(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_hex varchar2(400);
    l_column raw(200);
    l_ray number;
    l_light_base simple_integer := 0;
    l_texture_x simple_integer := 0;
    l_texture_y simple_integer := 0;
    l_step simple_integer := 0;
    l_pixel0 simple_integer:=0;l_pixel1 simple_integer:=0;
    l_pixel2 simple_integer:=0;l_pixel3 simple_integer:=0;
    l_pixel4 simple_integer:=0;l_pixel5 simple_integer:=0;
    l_pixel6 simple_integer:=0;l_pixel7 simple_integer:=0;
  begin
    initialize;
    p_chunk0 := null;
    p_chunk1 := null;
    p_checksum := 0;
    for x_ in 0..c_width - 1 loop
      l_ray := x_ + p_seed;
      l_ray := mod(l_ray * 1103515245 + 12345, 2147483648);
      l_light_base := mod(trunc(l_ray / 524288) + trunc(x_ / 16), 32) * 256;
      l_texture_x := mod(trunc(l_ray / 128), 64);
      l_texture_y := mod(p_seed + x_ * 3, 64);
      l_step := mod(trunc(l_ray / 8388608), 8) + 1;
      l_hex := null;
      for block_ in 0..24 loop
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel0 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel1 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel2 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel3 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel4 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel5 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel6 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_texture_y := bitand(l_texture_y + l_step, 63);
        l_pixel7 := g_colormaps(l_light_base +
          g_texture(l_texture_y * 64 + l_texture_x));
        l_hex := l_hex ||
          g_hex(l_pixel0)||g_hex(l_pixel1)||g_hex(l_pixel2)||g_hex(l_pixel3)||
          g_hex(l_pixel4)||g_hex(l_pixel5)||g_hex(l_pixel6)||g_hex(l_pixel7);
      end loop;
      l_column := hextoraw(l_hex);
      if x_ < 160 then
        p_chunk0 := utl_raw.concat(p_chunk0, l_column);
      else
        p_chunk1 := utl_raw.concat(p_chunk1, l_column);
      end if;
      p_checksum := p_checksum + l_pixel0;
    end loop;
  end render_hex_block_columns;

  procedure render_buffered_frame(
    p_seed in pls_integer,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_hex varchar2(400);
    l_column raw(200);
    l_ray number;
    l_light_base simple_integer:=0;l_texture_x simple_integer:=0;
    l_texture_y simple_integer:=0;l_step simple_integer:=0;
    l_pixel simple_integer:=0;l_base simple_integer:=0;
  begin
    initialize;p_chunk0:=null;p_chunk1:=null;p_checksum:=0;
    -- Compute into a retained framebuffer first. Real draw tapes revisit
    -- arbitrary destinations, so direct output streaming is not available.
    for x_ in 0..c_width-1 loop
      l_ray:=x_+p_seed;l_ray:=mod(l_ray*1103515245+12345,2147483648);
      l_light_base:=mod(trunc(l_ray/524288)+trunc(x_/16),32)*256;
      l_texture_x:=mod(trunc(l_ray/128),64);
      l_texture_y:=mod(p_seed+x_*3,64);
      l_step:=mod(trunc(l_ray/8388608),8)+1;l_base:=x_*c_height;
      for y_ in 0..c_height-1 loop
        l_texture_y:=bitand(l_texture_y+l_step,63);
        l_pixel:=g_colormaps(l_light_base+
          g_texture(l_texture_y*64+l_texture_x));
        g_frame(l_base+y_):=l_pixel;
      end loop;
    end loop;
    -- Serialize the completed column-major framebuffer in 200-byte columns.
    for x_ in 0..c_width-1 loop
      l_hex:=null;l_base:=x_*c_height;
      for block_ in 0..24 loop
        l_pixel:=l_base+block_*8;
        l_hex:=l_hex||g_hex(g_frame(l_pixel))||g_hex(g_frame(l_pixel+1))
          ||g_hex(g_frame(l_pixel+2))||g_hex(g_frame(l_pixel+3))
          ||g_hex(g_frame(l_pixel+4))||g_hex(g_frame(l_pixel+5))
          ||g_hex(g_frame(l_pixel+6))||g_hex(g_frame(l_pixel+7));
      end loop;
      l_column:=hextoraw(l_hex);
      if x_<160 then p_chunk0:=utl_raw.concat(p_chunk0,l_column);
      else p_chunk1:=utl_raw.concat(p_chunk1,l_column);end if;
      p_checksum:=p_checksum+g_frame(l_base);
    end loop;
  end render_buffered_frame;

  procedure render_command_stream(
    p_commands in raw,
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_commands_hex varchar2(1280);
    l_column raw(200);
    l_source_column pls_integer;
    l_light pls_integer;
  begin
    initialize;
    if utl_raw.length(p_commands) <> c_width * 2 then
      raise_application_error(-20882, 'render command stream must be 640 bytes');
    end if;
    l_commands_hex := rawtohex(p_commands);
    p_chunk0 := null;
    p_chunk1 := null;
    p_checksum := 0;
    for x_ in 0..c_width - 1 loop
      l_source_column := to_number(substr(l_commands_hex, x_ * 4 + 1, 2), 'XX');
      l_light := to_number(substr(l_commands_hex, x_ * 4 + 3, 2), 'XX');
      l_column := utl_raw.translate(g_columns(l_source_column),
        g_maps(l_light), g_from_set);
      if x_ < 160 then
        p_chunk0 := utl_raw.concat(p_chunk0, l_column);
      else
        p_chunk1 := utl_raw.concat(p_chunk1, l_column);
      end if;
      p_checksum := p_checksum + l_source_column + l_light;
    end loop;
  end render_command_stream;

  procedure reset_draw_calls is
  begin
    g_draw_checksum := 0;
  end reset_draw_calls;

  procedure consume_draw_call(
    p_kind in pls_integer,
    p0 in pls_integer,
    p1 in pls_integer,
    p2 in pls_integer,
    p3 in pls_integer,
    p4 in pls_integer,
    p5 in pls_integer,
    p6 in pls_integer
  ) is
  begin
    -- Retained-state control probe for the proposed renderer ABI. The real
    -- body consumes the same scalar fields and mutates g_frame directly.
    g_draw_checksum := g_draw_checksum + p_kind + p0 + p1 + p2 + p3 +
      p4 + p5 + p6;
  end consume_draw_call;

  procedure read_draw_checksum(p_checksum out pls_integer) is
  begin
    p_checksum := g_draw_checksum;
  end read_draw_checksum;

  procedure consume_draw_batch(p_commands in raw) is
  begin
    g_draw_checksum := g_draw_checksum + utl_raw.length(p_commands);
  end consume_draw_batch;


  procedure consume_draw_blob(p_commands in blob) is
    l_raw raw(32767);
    l_batch_hex varchar2(32767);
    l_word0 number;
    l_word1 number;
    l_kind simple_integer:=0;l_coordinate simple_integer:=0;
    l_ordinate simple_integer:=0;l_count simple_integer:=0;
    l_source simple_integer:=0;l_light simple_integer:=0;
    l_x simple_integer:=0;l_y simple_integer:=0;l_pixel simple_integer:=0;
    l_record simple_integer:=0;l_records simple_integer:=0;
    l_position simple_integer:=1;l_offset simple_integer:=1;
    l_stage varchar2(30):='start';
  begin
    initialize;
    if mod(dbms_lob.getlength(p_commands),16)<>0 then
      raise_application_error(-20886,'draw BLOB must contain 16-byte records');
    end if;
    l_records:=dbms_lob.getlength(p_commands)/16;
    while l_record<l_records loop
      l_count:=least(1000,l_records-l_record);
      l_stage:='lob-substr';
      l_raw:=dbms_lob.substr(p_commands,l_count*16,l_position);
      l_batch_hex:=rawtohex(l_raw);
      l_offset:=1;
      for batch_record_ in 1..l_count loop
        l_stage:='word0';
        -- The MLE producer stores network-order words, allowing one bulk
        -- RAWTOHEX per batch rather than thousands of UTL_RAW calls.
        l_word0:=to_number(substr(l_batch_hex,(l_offset-1)*2+1,8),'XXXXXXXX');
        l_word1:=to_number(substr(l_batch_hex,(l_offset-1)*2+9,8),'XXXXXXXX');
        l_stage:='fields';
        l_kind:=bitand(l_word0,255);
        l_coordinate:=bitand(l_word0,16776960)/256;
        l_ordinate:=bitand(l_word0,2130706432)/16777216+
          case when l_word0>=2147483648 then 128 else 0 end;
        l_count:=bitand(l_word1,255);
        l_source:=bitand(l_word1,65280)/256;
        l_light:=bitand(l_word1,16711680)/65536;
        if l_kind=1 then
          l_stage:='column';
          l_x:=mod(l_coordinate,c_width);
          l_count:=least(l_count,c_height);
          l_y:=mod(l_ordinate,c_height-l_count+1);
          for pixel_ in 0..l_count-1 loop
            l_pixel:=g_colormaps(l_light*256+g_texture(
              bitand(l_source+pixel_*3,63)*64+bitand(l_source,63)));
            g_frame(l_x*c_height+l_y+pixel_):=l_pixel;
          end loop;
        elsif l_kind=2 then
          l_stage:='span';
          l_count:=least(l_count,c_width);
          l_x:=mod(l_coordinate,c_width-l_count+1);
          l_y:=mod(l_ordinate,c_height);
          for pixel_ in 0..l_count-1 loop
            l_pixel:=g_colormaps(l_light*256+g_texture(
              bitand(l_source+pixel_*5,63)*64+
              bitand(l_source+pixel_*3,63)));
            g_frame((l_x+pixel_)*c_height+l_y):=l_pixel;
          end loop;
        end if;
        l_offset:=l_offset+16;l_record:=l_record+1;
      end loop;
      l_position:=l_position+utl_raw.length(l_raw);
    end loop;
    g_draw_checksum:=l_records;
  exception when others then
    raise_application_error(-20888,'draw parse record='||l_record||
      ' position='||l_position||' offset='||l_offset||' stage='||l_stage||
      ' rawlen='||nvl(utl_raw.length(l_raw),-1)||' first='||
      rawtohex(utl_raw.substr(l_raw,1,16))||' cause='||sqlerrm);
  end consume_draw_blob;

  procedure finish_draw_frame(
    p_chunk0 out raw,
    p_chunk1 out raw,
    p_checksum out pls_integer
  ) is
    l_hex varchar2(400);l_column raw(200);
    l_base simple_integer:=0;l_pixel simple_integer:=0;
  begin
    initialize;p_chunk0:=null;p_chunk1:=null;p_checksum:=0;
    for x_ in 0..c_width-1 loop
      l_hex:=null;l_base:=x_*c_height;
      for block_ in 0..24 loop
        l_pixel:=l_base+block_*8;
        l_hex:=l_hex||g_hex(g_frame(l_pixel))||g_hex(g_frame(l_pixel+1))
          ||g_hex(g_frame(l_pixel+2))||g_hex(g_frame(l_pixel+3))
          ||g_hex(g_frame(l_pixel+4))||g_hex(g_frame(l_pixel+5))
          ||g_hex(g_frame(l_pixel+6))||g_hex(g_frame(l_pixel+7));
      end loop;
      l_column:=hextoraw(l_hex);
      if x_<160 then p_chunk0:=utl_raw.concat(p_chunk0,l_column);
      else p_chunk1:=utl_raw.concat(p_chunk1,l_column);end if;
      p_checksum:=p_checksum+g_frame(l_base);
    end loop;
  end finish_draw_frame;
end doom_mle_native_bench;
/

alter package doom_mle_native_bench compile body
  plsql_code_type=native plsql_optimize_level=3;
