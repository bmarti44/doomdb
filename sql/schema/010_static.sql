create table doom_config (
  config_key varchar2(64) not null,
  number_value number,
  text_value varchar2(4000),
  constraint doom_config_pk primary key (config_key),
  constraint doom_config_one_value_ck check (
    (number_value is not null and text_value is null) or
    (number_value is null and text_value is not null))
);

create table doom_wad_source (
  directory_index number(10) not null,
  lump_name varchar2(8) not null,
  occurrence_index number(10) not null,
  lump_offset number(12) not null,
  lump_size number(12) not null,
  sha256 varchar2(64) not null,
  selection_rule varchar2(20) not null,
  constraint doom_wad_source_pk primary key (directory_index),
  constraint doom_wad_source_name_uq unique (lump_name, occurrence_index),
  constraint doom_wad_source_num_ck check (
    directory_index >= 0 and occurrence_index >= 0 and lump_offset >= 0 and lump_size >= 0),
  constraint doom_wad_source_sha_ck check (regexp_like(sha256, '^[0-9a-f]{64}$')),
  constraint doom_wad_source_rule_ck check (selection_rule in ('map-confined','last-occurrence'))
);

create table doom_asset (
  asset_id number(10) not null,
  asset_kind varchar2(20) not null,
  asset_name varchar2(32) not null,
  width number(10),
  height number(10),
  first_opaque_x number(10),
  first_opaque_y number(10),
  raw_sha256 varchar2(64),
  texel_sha256 varchar2(64),
  constraint doom_asset_pk primary key (asset_id),
  constraint doom_asset_identity_uq unique (asset_kind, asset_name),
  constraint doom_asset_id_ck check (asset_id >= 0),
  constraint doom_asset_dim_ck check (
    (width is null and height is null) or (width > 0 and height > 0)),
  constraint doom_asset_first_opaque_ck check (
    (first_opaque_x is null and first_opaque_y is null) or
    (first_opaque_x between 0 and width-1 and first_opaque_y between 0 and height-1)),
  constraint doom_asset_hash_present_ck check (raw_sha256 is not null or texel_sha256 is not null),
  constraint doom_asset_raw_sha_ck check (raw_sha256 is null or regexp_like(raw_sha256, '^[0-9a-f]{64}$')),
  constraint doom_asset_texel_sha_ck check (texel_sha256 is null or regexp_like(texel_sha256, '^[0-9a-f]{64}$'))
);

create table doom_asset_source (
  asset_kind varchar2(20) not null,
  asset_name varchar2(32) not null,
  source_ordinal number(10) not null,
  lump_name varchar2(8) not null,
  source_sha256 varchar2(64) not null,
  constraint doom_asset_source_pk primary key (asset_kind, asset_name, source_ordinal),
  constraint doom_asset_source_asset_fk foreign key (asset_kind, asset_name)
    references doom_asset (asset_kind, asset_name),
  constraint doom_asset_source_ord_ck check (source_ordinal >= 0),
  constraint doom_asset_source_sha_ck check (regexp_like(source_sha256, '^[0-9a-f]{64}$'))
);

create table doom_asset_blob (
  asset_id number(10) not null,
  media_type varchar2(100) not null,
  encoded_bytes blob not null,
  constraint doom_asset_blob_pk primary key (asset_id),
  constraint doom_asset_blob_asset_fk foreign key (asset_id) references doom_asset (asset_id)
);

create table doom_renderer_asset_pack (
  asset_kind varchar2(20) not null,
  format_version number(4) not null,
  element_count number(12) not null,
  payload_sha256 varchar2(64) not null,
  encoded_bytes blob not null,
  constraint doom_renderer_asset_pack_pk primary key (asset_kind),
  constraint doom_renderer_asset_pack_version_ck check (format_version=1),
  constraint doom_renderer_asset_pack_count_ck check (element_count>0),
  constraint doom_renderer_asset_pack_sha_ck check
    (regexp_like(payload_sha256,'^[0-9a-f]{64}$'))
);

create table at (
  a number(10) not null,
  x number(10) not null,
  y number(10) not null,
  c number(3) not null,
  constraint at_coord_ck check (x >= 0 and y >= 0),
  constraint at_palette_ck check (c between -1 and 255)
);

create table doom_palette_texel (
  palette_index number(3) not null,
  red number(3) not null,
  green number(3) not null,
  blue number(3) not null,
  constraint doom_palette_texel_pk primary key (palette_index),
  constraint doom_palette_index_ck check (palette_index between 0 and 255),
  constraint doom_palette_rgb_ck check (red between 0 and 255 and green between 0 and 255 and blue between 0 and 255)
);

create table doom_colormap_texel (
  map_index number(2) not null,
  palette_index number(3) not null,
  mapped_index number(3) not null,
  constraint doom_colormap_texel_pk primary key (map_index, palette_index),
  constraint doom_colormap_map_ck check (map_index between 0 and 31),
  constraint doom_colormap_palette_fk foreign key (palette_index) references doom_palette_texel (palette_index),
  constraint doom_colormap_mapped_fk foreign key (mapped_index) references doom_palette_texel (palette_index)
);

create table doom_reject_byte (
  byte_offset number(10) not null,
  byte_value number(3) not null,
  constraint doom_reject_byte_pk primary key (byte_offset),
  constraint doom_reject_byte_ck check (byte_offset >= 0 and byte_value between 0 and 255)
);

create table doom_blockmap_byte (
  byte_offset number(10) not null,
  byte_value number(3) not null,
  constraint doom_blockmap_byte_pk primary key (byte_offset),
  constraint doom_blockmap_byte_ck check (byte_offset >= 0 and byte_value between 0 and 255)
);

create table doom_map_vertex (
  vertex_id number(10) not null,
  x number(10) not null,
  y number(10) not null,
  constraint doom_map_vertex_pk primary key (vertex_id),
  constraint doom_map_vertex_id_ck check (vertex_id >= 0)
);

create table doom_map_sector (
  sector_id number(10) not null,
  floor_height number(10) not null,
  ceiling_height number(10) not null,
  floor_flat varchar2(32) not null,
  ceiling_flat varchar2(32) not null,
  light_level number(3) not null,
  special number(10) not null,
  tag number(10) not null,
  constraint doom_map_sector_pk primary key (sector_id),
  constraint doom_map_sector_id_ck check (sector_id >= 0),
  constraint doom_map_sector_height_ck check (ceiling_height >= floor_height),
  constraint doom_map_sector_light_ck check (light_level between 0 and 255),
  constraint doom_map_sector_special_ck check (special >= 0 and tag >= 0)
);

create table doom_map_thing (
  thing_id number(10) not null,
  x number(10) not null,
  y number(10) not null,
  angle number(3) not null,
  thing_type number(10) not null,
  flags number(10) not null,
  constraint doom_map_thing_pk primary key (thing_id),
  constraint doom_map_thing_id_ck check (thing_id >= 0),
  constraint doom_map_thing_angle_ck check (angle between 0 and 359),
  constraint doom_map_thing_type_ck check (thing_type > 0),
  constraint doom_map_thing_flags_ck check (flags >= 0)
);

create table doom_map_sidedef (
  sidedef_id number(10) not null,
  x_offset number(10) not null,
  y_offset number(10) not null,
  upper_texture varchar2(32) not null,
  lower_texture varchar2(32) not null,
  middle_texture varchar2(32) not null,
  sector_id number(10) not null,
  constraint doom_map_sidedef_pk primary key (sidedef_id),
  constraint doom_map_sidedef_id_ck check (sidedef_id >= 0),
  constraint doom_map_sidedef_sector_fk foreign key (sector_id) references doom_map_sector (sector_id)
);

create table doom_map_linedef (
  linedef_id number(10) not null,
  start_vertex_id number(10) not null,
  end_vertex_id number(10) not null,
  flags number(10) not null,
  special number(10) not null,
  tag number(10) not null,
  right_sidedef_id number(10) not null,
  left_sidedef_id number(10),
  constraint doom_map_linedef_pk primary key (linedef_id),
  constraint doom_map_linedef_id_ck check (linedef_id >= 0),
  constraint doom_map_linedef_vertex_ck check (start_vertex_id != end_vertex_id),
  constraint doom_map_linedef_num_ck check (flags >= 0 and special >= 0 and tag >= 0),
  constraint doom_map_linedef_start_fk foreign key (start_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_map_linedef_end_fk foreign key (end_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_map_linedef_right_fk foreign key (right_sidedef_id) references doom_map_sidedef (sidedef_id),
  constraint doom_map_linedef_left_fk foreign key (left_sidedef_id) references doom_map_sidedef (sidedef_id)
);

create table doom_linedef (
  linedef_id number(10) not null,
  start_vertex_id number(10) not null,
  end_vertex_id number(10) not null,
  flags number(10) not null,
  special number(10) not null,
  tag number(10) not null,
  right_sidedef_id number(10) not null,
  left_sidedef_id number(10),
  geom mdsys.sdo_geometry,
  length number,
  direction_x number,
  direction_y number,
  constraint doom_linedef_pk primary key (linedef_id),
  constraint doom_linedef_vertex_ck check (start_vertex_id != end_vertex_id),
  constraint doom_linedef_num_ck check (linedef_id >= 0 and flags >= 0 and special >= 0 and tag >= 0),
  constraint doom_linedef_start_fk foreign key (start_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_linedef_end_fk foreign key (end_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_linedef_right_fk foreign key (right_sidedef_id) references doom_map_sidedef (sidedef_id),
  constraint doom_linedef_left_fk foreign key (left_sidedef_id) references doom_map_sidedef (sidedef_id)
);

create table doom_map_seg (
  seg_id number(10) not null,
  start_vertex_id number(10) not null,
  end_vertex_id number(10) not null,
  angle number(5) not null,
  linedef_id number(10) not null,
  direction number(1) not null,
  offset number(10) not null,
  constraint doom_map_seg_pk primary key (seg_id),
  constraint doom_map_seg_id_ck check (seg_id >= 0),
  constraint doom_map_seg_angle_ck check (angle between 0 and 65535),
  constraint doom_map_seg_direction_ck check (direction in (0,1)),
  constraint doom_map_seg_offset_ck check (offset >= 0),
  constraint doom_map_seg_start_fk foreign key (start_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_map_seg_end_fk foreign key (end_vertex_id) references doom_map_vertex (vertex_id),
  constraint doom_map_seg_linedef_fk foreign key (linedef_id) references doom_map_linedef (linedef_id)
);

create table doom_map_ssector (
  ssector_id number(10) not null,
  seg_count number(10) not null,
  first_seg_id number(10) not null,
  constraint doom_map_ssector_pk primary key (ssector_id),
  constraint doom_map_ssector_num_ck check (ssector_id >= 0 and seg_count > 0),
  constraint doom_map_ssector_seg_fk foreign key (first_seg_id) references doom_map_seg (seg_id)
);

create table doom_map_node (
  node_id number(10) not null,
  x number(10) not null, y number(10) not null, dx number(10) not null, dy number(10) not null,
  bbox0_top number(10) not null, bbox0_bottom number(10) not null,
  bbox0_left number(10) not null, bbox0_right number(10) not null,
  bbox1_top number(10) not null, bbox1_bottom number(10) not null,
  bbox1_left number(10) not null, bbox1_right number(10) not null,
  child0_is_ssector number(1) not null, child0_id number(10) not null,
  child1_is_ssector number(1) not null, child1_id number(10) not null,
  constraint doom_map_node_pk primary key (node_id),
  constraint doom_map_node_id_ck check (node_id >= 0),
  constraint doom_map_node_delta_ck check (dx != 0 or dy != 0),
  constraint doom_map_node_bbox_ck check (
    bbox0_top >= bbox0_bottom and bbox0_right >= bbox0_left and
    bbox1_top >= bbox1_bottom and bbox1_right >= bbox1_left),
  constraint doom_map_node_child_ck check (
    child0_is_ssector in (0,1) and child1_is_ssector in (0,1) and child0_id >= 0 and child1_id >= 0)
);

create or replace view doom_vertex as
select vertex_id, x, y from doom_map_vertex;

create table doom_patch_placement (
  texture_asset_id number(10) not null,
  patch_ordinal number(10) not null,
  patch_asset_id number(10) not null,
  origin_x number(10) not null,
  origin_y number(10) not null,
  constraint doom_patch_placement_pk primary key (texture_asset_id, patch_ordinal),
  constraint doom_patch_texture_fk foreign key (texture_asset_id) references doom_asset (asset_id),
  constraint doom_patch_source_fk foreign key (patch_asset_id) references doom_asset (asset_id),
  constraint doom_patch_ordinal_ck check (patch_ordinal >= 0)
);

create table doom_sprite_rotation (
  state_id varchar2(64) not null,
  rotation number(2) not null,
  asset_id number(10) not null,
  mirrored number(1) not null,
  constraint doom_sprite_rotation_pk primary key (state_id, rotation),
  constraint doom_sprite_rotation_asset_fk foreign key (asset_id) references doom_asset (asset_id),
  constraint doom_sprite_rotation_num_ck check (rotation between 0 and 8 and mirrored in (0,1))
);

create table doom_sound (
  sound_id varchar2(32) not null,
  asset_id number(10) not null,
  sample_rate number(10),
  sample_count number(12),
  pcm_blob blob,
  constraint doom_sound_pk primary key (sound_id),
  constraint doom_sound_asset_uq unique (asset_id),
  constraint doom_sound_asset_fk foreign key (asset_id) references doom_asset (asset_id),
  constraint doom_sound_sample_ck check (
    (sample_rate is null and sample_count is null and pcm_blob is null) or
    (sample_rate > 0 and sample_count >= 0 and pcm_blob is not null))
);

create table doom_music (
  music_id varchar2(32) not null,
  asset_id number(10) not null,
  media_type varchar2(100) not null,
  playable_blob blob,
  constraint doom_music_pk primary key (music_id),
  constraint doom_music_asset_uq unique (asset_id),
  constraint doom_music_asset_fk foreign key (asset_id) references doom_asset (asset_id)
);
