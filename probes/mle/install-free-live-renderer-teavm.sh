#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_name=doom-mle-free-live-renderer.js
if [[ "${PMLE_FREE_LIVE_WORLD_ARTIFACT:-NO}" == YES ]]; then
  artifact_name=doom-mle-free-live-world-raster.js
fi
if [[ "${PMLE_FREE_LIVE_UNIFIED_ARTIFACT:-NO}" == YES ]]; then
  [[ "${PMLE_FREE_LIVE_WORLD_ARTIFACT:-NO}" == YES ]] || {
    printf '%s\n' 'unified artifact requires world mode' >&2;exit 2; }
  artifact_name=doom-mle-free-live-unified-renderer.js
fi
source_file="$root/probes/mle/free-live-teavm/target/javascript/$artifact_name"
compositor_file="$root/probes/mle/free-live-teavm/target/javascript/doom-mle-free-live-compositor.js"
compositor_pack_file="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
pack_file="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
if [[ "${PMLE_FREE_LIVE_WORLD_ARTIFACT:-NO}" == YES ]]; then
  pack_file="$root/probes/mle/free-live-teavm/target/world-raster-pack/free-live-render.pack"
fi
asset_directory="$root/probes/mle/target/free-live-renderer/assets-v1"
wall_file="$asset_directory/wall_texture.bin"
flat_file="$asset_directory/flat.bin"
sprite_file="$asset_directory/sprite_patch.bin"
ui_file="$asset_directory/ui_patch.bin"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
for input in \
  "$source_file" "$pack_file" "$wall_file" "$flat_file" \
  "$sprite_file" "$ui_file"; do
  [[ -s "$input" && ! -L "$input" ]] || exit 2
done
if [[ "${PMLE_FREE_LIVE_WORLD_ARTIFACT:-NO}" == YES ]]; then
  [[ -s "$compositor_file" && ! -L "$compositor_file"
      && -s "$compositor_pack_file" && ! -L "$compositor_pack_file" ]] || exit 2
  compositor_sha="$(shasum -a 256 "$compositor_file" | awk '{print $1}')"
  compositor_bytes="$(wc -c <"$compositor_file" | tr -d '[:space:]')"
  compositor_pack_sha="$(shasum -a 256 "$compositor_pack_file" | awk '{print $1}')"
  compositor_pack_bytes="$(wc -c <"$compositor_pack_file" | tr -d '[:space:]')"
fi
source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
source_bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"
pack_sha="$(shasum -a 256 "$pack_file" | awk '{print $1}')"
pack_bytes="$(wc -c <"$pack_file" | tr -d '[:space:]')"
wall_sha="$(shasum -a 256 "$wall_file" | awk '{print $1}')"
wall_bytes="$(wc -c <"$wall_file" | tr -d '[:space:]')"
flat_sha="$(shasum -a 256 "$flat_file" | awk '{print $1}')"
flat_bytes="$(wc -c <"$flat_file" | tr -d '[:space:]')"
sprite_sha="$(shasum -a 256 "$sprite_file" | awk '{print $1}')"
sprite_bytes="$(wc -c <"$sprite_file" | tr -d '[:space:]')"
ui_sha="$(shasum -a 256 "$ui_file" | awk '{print $1}')"
ui_bytes="$(wc -c <"$ui_file" | tr -d '[:space:]')"

emit_blob() {
  local file="$1" target="$2"
  base64 <"$file" | tr -d '\r\n' | fold -w 2000 |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf 'dbms_lob.writeappend(%s,utl_raw.length(l_raw),l_raw);\n' "$target"
    done
}

printf '%s\n' \
  'whenever oserror exit failure rollback' \
  'whenever sqlerror exit sql.sqlcode rollback' \
  'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
  'set serveroutput on size unlimited'
for object in \
  'function doom_free_gen_screen' \
  'function doom_free_gen_menu_select' \
  'function doom_free_gen_menu' \
  'function doom_free_gen_title' \
  'function doom_free_gen_world' \
  'function doom_free_gen_world_geometry' \
  'function doom_free_gen_load_dynamics' \
  'function doom_free_gen_loaded_geometry' \
  'function doom_free_gen_world_sprites' \
  'function doom_free_gen_weapon' \
  'function doom_free_gen_status' \
  'function doom_free_gen_ui_finalize' \
  'function doom_free_gen_ui_load' \
  'function doom_free_gen_ui_allocate' \
  'function doom_free_gen_sprite_finalize' \
  'function doom_free_gen_sprite_load' \
  'function doom_free_gen_sprite_allocate' \
  'function doom_free_gen_flat_finalize' \
  'function doom_free_gen_flat_load' \
  'function doom_free_gen_flat_allocate' \
  'function doom_free_gen_native_reset' \
  'function doom_free_gen_lit_chunk' \
  'function doom_free_gen_lit_length' \
  'function doom_free_gen_resolved_chunk' \
  'function doom_free_gen_resolved' \
  'function doom_free_gen_raster_writes' \
  'function doom_free_gen_native_misses' \
  'function doom_free_gen_native_commands' \
  'function doom_free_gen_native_record_length' \
  'function doom_free_gen_native_chunk' \
  'function doom_free_gen_native_tape' \
  'function doom_free_gen_frame_chunk' \
  'function doom_free_gen_live_loaded_coarse' \
  'function doom_free_gen_live_load' \
  'function doom_free_gen_live_coarse' \
  'function doom_free_gen_frame_batch' 'function doom_free_gen_frame' \
  'function doom_free_gen_walls_only' 'function doom_free_gen_planes_only' \
  'function doom_free_gen_texture_finalize' \
  'function doom_free_gen_texture_load' \
  'function doom_free_gen_texture_allocate' \
  'function doom_free_gen_batch' 'function doom_free_gen_render' \
  'function doom_free_gen_finalize' 'function doom_free_gen_load' \
  'function doom_free_gen_allocate'; do
  printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$object"
done
printf '%s\n' \
  "begin execute immediate 'drop mle module doom_free_generated_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
  '/' \
  "begin execute immediate 'drop table doom_free_generated_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
  '/' \
  'create table doom_free_generated_source(' \
  'source_blob blob not null,pack_blob blob not null,' \
  'wall_blob blob not null,flat_blob blob not null,' \
  'sprite_blob blob not null,ui_blob blob not null,' \
  'source_bytes number not null,source_sha varchar2(64) not null,' \
  'pack_bytes number not null,pack_sha varchar2(64) not null,' \
  'wall_bytes number not null,wall_sha varchar2(64) not null,' \
  'flat_bytes number not null,flat_sha varchar2(64) not null,' \
  'sprite_bytes number not null,sprite_sha varchar2(64) not null,' \
  'ui_bytes number not null,ui_sha varchar2(64) not null);' \
  "insert into doom_free_generated_source values(empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),$source_bytes,'$source_sha',$pack_bytes,'$pack_sha',$wall_bytes,'$wall_sha',$flat_bytes,'$flat_sha',$sprite_bytes,'$sprite_sha',$ui_bytes,'$ui_sha');" \
  'declare l_source blob;l_pack blob;l_wall blob;l_flat blob;l_sprite blob;l_ui blob;l_raw raw(32767);begin' \
  'select source_blob,pack_blob,wall_blob,flat_blob,sprite_blob,ui_blob' \
  'into l_source,l_pack,l_wall,l_flat,l_sprite,l_ui' \
  'from doom_free_generated_source for update;'
emit_blob "$source_file" l_source
emit_blob "$pack_file" l_pack
emit_blob "$wall_file" l_wall
emit_blob "$flat_file" l_flat
emit_blob "$sprite_file" l_sprite
emit_blob "$ui_file" l_ui
printf '%s\n' \
  'end;' \
  '/' \
  'declare l_count number;begin' \
  'select count(*) into l_count from doom_free_generated_source' \
  'where dbms_lob.getlength(source_blob)=source_bytes' \
  'and dbms_lob.getlength(pack_blob)=pack_bytes' \
  'and dbms_lob.getlength(wall_blob)=wall_bytes' \
  'and dbms_lob.getlength(flat_blob)=flat_bytes' \
  'and dbms_lob.getlength(sprite_blob)=sprite_bytes' \
  'and dbms_lob.getlength(ui_blob)=ui_bytes' \
  'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha' \
  'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha' \
  'and lower(rawtohex(dbms_crypto.hash(wall_blob,dbms_crypto.hash_sh256)))=wall_sha' \
  'and lower(rawtohex(dbms_crypto.hash(flat_blob,dbms_crypto.hash_sh256)))=flat_sha' \
  'and lower(rawtohex(dbms_crypto.hash(sprite_blob,dbms_crypto.hash_sh256)))=sprite_sha' \
  'and lower(rawtohex(dbms_crypto.hash(ui_blob,dbms_crypto.hash_sh256)))=ui_sha;' \
  "if l_count<>1 then raise_application_error(-20796,'generated renderer staging mismatch');end if;" \
  "dbms_output.put_line('PMLE_FREE_LIVE_TEAVM_STAGING|PASS|source_bytes=$source_bytes|source_sha256=$source_sha|pack_bytes=$pack_bytes|pack_sha256=$pack_sha|wall_bytes=$wall_bytes|wall_sha256=$wall_sha|flat_bytes=$flat_bytes|flat_sha256=$flat_sha|sprite_bytes=$sprite_bytes|sprite_sha256=$sprite_sha|ui_bytes=$ui_bytes|ui_sha256=$ui_sha');end;" \
  '/' \
  'create mle module doom_free_generated_renderer language javascript using blob' \
  '(select source_blob from doom_free_generated_source);' \
  '/' \
  "create function doom_free_gen_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocatePack(number)';" \
  '/' \
  "create function doom_free_gen_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadPackChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_finalize return number as mle module doom_free_generated_renderer signature 'finalizePack()';" \
  '/' \
  "create function doom_free_gen_render(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderGeometry(number)';" \
  '/' \
  "create function doom_free_gen_batch(p_start number,p_count number)return number as mle module doom_free_generated_renderer signature 'renderGeometryBatch(number, number)';" \
  '/' \
  "create function doom_free_gen_texture_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocateWallTextures(number)';" \
  '/' \
  "create function doom_free_gen_texture_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadWallTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_texture_finalize return number as mle module doom_free_generated_renderer signature 'finalizeWallTextures()';" \
  '/' \
  "create function doom_free_gen_flat_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocateFlatTextures(number)';" \
  '/' \
  "create function doom_free_gen_flat_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadFlatTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_flat_finalize return number as mle module doom_free_generated_renderer signature 'finalizeFlatTextures()';" \
  '/' \
  "create function doom_free_gen_sprite_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocateSpriteTextures(number)';" \
  '/' \
  "create function doom_free_gen_sprite_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadSpriteTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_sprite_finalize return number as mle module doom_free_generated_renderer signature 'finalizeSpriteTextures()';" \
  '/' \
  "create function doom_free_gen_ui_allocate(p_length number)return number as mle module doom_free_generated_renderer signature 'allocateUiTextures(number)';" \
  '/' \
  "create function doom_free_gen_ui_load(p_offset number,p_chunk raw)return number as mle module doom_free_generated_renderer signature 'loadUiTextureChunk(number, Uint8Array)';" \
  '/' \
  "create function doom_free_gen_ui_finalize return number as mle module doom_free_generated_renderer signature 'finalizeUiTextures()';" \
  '/' \
  "create function doom_free_gen_world(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderWorldSnapshot(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_world_geometry(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderWorldGeometryStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_load_dynamics(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'loadWorldDynamicsStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_loaded_geometry(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderLoadedWorldGeometryStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_world_sprites(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderWorldSpritesStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_weapon(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderWeaponStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_status(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderStatusStage(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_title return number as mle module doom_free_generated_renderer signature 'renderTitleFrame()';" \
  '/' \
  "create function doom_free_gen_menu(p_page number)return number as mle module doom_free_generated_renderer signature 'renderMenuFrame(number)';" \
  '/' \
  "create function doom_free_gen_menu_select(p_page number,p_selection number,p_tic number)return number as mle module doom_free_generated_renderer signature 'renderMenuSelectionFrame(number, number, number)';" \
  '/' \
  "create function doom_free_gen_screen(p_screen number)return number as mle module doom_free_generated_renderer signature 'renderScreenFrame(number)';" \
  '/' \
  "create function doom_free_gen_frame(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderFrame(number)';" \
  '/' \
  "create function doom_free_gen_frame_coarse(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderFrameCoarseVertical(number)';" \
  '/' \
  "create function doom_free_gen_live_coarse(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderLiveFrameCoarse(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_live_load(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'loadLiveSnapshot(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_live_loaded_coarse(p_snapshot raw)return number as mle module doom_free_generated_renderer signature 'renderLoadedLiveFrameCoarse(Uint8Array)';" \
  '/' \
  "create function doom_free_gen_walls_only(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderWallsOnly(number)';" \
  '/' \
  "create function doom_free_gen_planes_only(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderPlanesOnly(number)';" \
  '/' \
  "create function doom_free_gen_frame_batch(p_start number,p_count number)return number as mle module doom_free_generated_renderer signature 'renderFrameBatch(number, number)';" \
  '/' \
  "create function doom_free_gen_frame_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'frameChunk(number, number)';" \
  '/' \
  "create function doom_free_gen_native_tape(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderNativeTape(number)';" \
  '/' \
  "create function doom_free_gen_native_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'nativeTapeChunk(number, number)';" \
  '/' \
  "create function doom_free_gen_native_record_length(p_offset number,p_maximum number)return number as mle module doom_free_generated_renderer signature 'nativeTapeRecordChunkLength(number, number)';" \
  '/' \
  "create function doom_free_gen_native_commands return number as mle module doom_free_generated_renderer signature 'nativeTapeCommandCount()';" \
  '/' \
  "create function doom_free_gen_native_misses return number as mle module doom_free_generated_renderer signature 'nativeTapeMissCount()';" \
  '/' \
  "create function doom_free_gen_native_reset return number as mle module doom_free_generated_renderer signature 'resetNativeCache()';" \
  '/' \
  "create function doom_free_gen_raster_writes return number as mle module doom_free_generated_renderer signature 'rasterPixelWrites()';" \
  '/' \
  "create function doom_free_gen_resolved(p_pose number)return number as mle module doom_free_generated_renderer signature 'renderResolvedCommands(number)';" \
  '/' \
  "create function doom_free_gen_resolved_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'resolvedCommandChunk(number, number)';" \
  '/' \
  "create function doom_free_gen_lit_length return number as mle module doom_free_generated_renderer signature 'litTextureLength()';" \
  '/' \
  "create function doom_free_gen_lit_chunk(p_offset number,p_length number)return raw as mle module doom_free_generated_renderer signature 'litTextureChunk(number, number)';" \
  '/' \
  'commit;'

if [[ "${PMLE_FREE_LIVE_WORLD_ARTIFACT:-NO}" == YES ]]; then
  printf '%s\n' \
    "begin execute immediate 'drop mle module doom_free_live_compositor';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_free_compositor_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_free_compositor_source(' \
    'source_blob blob not null,pack_blob blob not null,' \
    'source_bytes number not null,source_sha varchar2(64) not null,' \
    'pack_bytes number not null,pack_sha varchar2(64) not null);' \
    "insert into doom_free_compositor_source values(empty_blob(),empty_blob(),$compositor_bytes,'$compositor_sha',$compositor_pack_bytes,'$compositor_pack_sha');" \
    'declare l_source blob;l_pack blob;l_raw raw(32767);begin' \
    'select source_blob,pack_blob into l_source,l_pack from doom_free_compositor_source for update;'
  emit_blob "$compositor_file" l_source
  emit_blob "$compositor_pack_file" l_pack
  printf '%s\n' \
    'end;' \
    '/' \
    'declare l_count number;begin' \
    'select count(*) into l_count from doom_free_compositor_source' \
    'where dbms_lob.getlength(source_blob)=source_bytes' \
    'and dbms_lob.getlength(pack_blob)=pack_bytes' \
    'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=source_sha' \
    'and lower(rawtohex(dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)))=pack_sha;' \
    "if l_count<>1 then raise_application_error(-20796,'compositor staging mismatch');end if;" \
    "dbms_output.put_line('PMLE_FREE_LIVE_COMPOSITOR_STAGING|PASS|source_bytes=$compositor_bytes|source_sha256=$compositor_sha|pack_bytes=$compositor_pack_bytes|pack_sha256=$compositor_pack_sha');end;" \
    '/' \
    'create mle module doom_free_live_compositor language javascript using blob' \
    '(select source_blob from doom_free_compositor_source);' \
    '/' \
    'commit;'
fi
