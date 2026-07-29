#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
plain="${PMLE_DVL2_PLAIN_RENDERER:-NO}"
world="${PMLE_DVL2_WORLD_RENDERER:-NO}"
unified="${PMLE_DVL2_UNIFIED_RENDERER:-NO}"
[[ "$plain" == YES || "$plain" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_PLAIN_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$world" == YES || "$world" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_WORLD_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$unified" == YES || "$unified" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_UNIFIED_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$unified" != YES || "$world" == YES ]] || {
  printf '%s\n' 'unified renderer requires world mode' >&2;exit 2; }
[[ "$plain" != YES || "$world" != YES ]] || {
  printf '%s\n' 'plain and world renderer modes are mutually exclusive' >&2;exit 2; }
if [[ "$world" == YES ]]; then
  source_file="$root/probes/mle/dvl2-world-raster-coordinator.mjs"
  renderer_module=doom_free_generated_renderer
  renderer_alias=doom_live_renderer
  renderer_kind=$([[ "$unified" == YES ]] &&
    printf TEAVM_UNIFIED_WORLD || printf TEAVM_SLIM_WORLD)
elif [[ "$plain" == YES ]]; then
  source_file="$root/probes/mle/plain-dvl2-render-coordinator.mjs"
  renderer_module=doom_plain_live_renderer
  renderer_alias=doom_plain_renderer
  renderer_kind=PLAIN_JS
else
  source_file="$root/probes/mle/dvl2-render-coordinator.mjs"
  renderer_module=doom_free_generated_renderer
  renderer_alias=doom_live_renderer
  renderer_kind=TEAVM
fi
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2
  exit 2
}
[[ -s "$source_file" && ! -L "$source_file" ]] || exit 2
bytes="$(wc -c <"$source_file" | tr -d '[:space:]')"
sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"

emit_blob() {
  base64 <"$source_file" | tr -d '\r\n' | fold -w 2000 |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf 'dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);\n'
    done
}

cat <<'SQL'
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited
begin execute immediate 'drop procedure doom_fused_release';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
SQL
for function in \
  publish_locator native_view_verify compose_status compose_weapon compose_sprites compose_copy compose_export \
  compose_build compose_prepare compose publish frame_chunk \
  compositor_ui_finalize compositor_ui_load compositor_ui_allocate \
  compositor_sprite_finalize compositor_sprite_load compositor_sprite_allocate \
  compositor_pack_finalize compositor_pack_load compositor_pack_allocate \
  set_range stage_render stage_import stage_prepare stage_geometry stage_walls stage_load step_only \
  render_temporal \
  step_commands step_render_fast step_render_static \
  step_render render_current init \
  ui_finalize ui_load ui_allocate sprite_finalize sprite_load sprite_allocate \
  flat_finalize flat_load flat_allocate wall_finalize wall_load wall_allocate \
  pack_finalize pack_load pack_allocate table_load table_allocate load allocate
do
  printf "begin execute immediate 'drop function doom_fused_%s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
    "$function"
done
cat <<'SQL'
begin execute immediate 'drop mle module doom_dvl2_render_coordinator';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_dvl2_render_env';exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;
/
begin execute immediate 'drop table doom_dvl2_render_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
SQL
printf '%s\n' \
  'create table doom_dvl2_render_source(source_blob blob not null,source_bytes number not null,source_sha varchar2(64) not null);' \
  "insert into doom_dvl2_render_source values(empty_blob(),$bytes,'$sha');" \
  'declare l_blob blob;l_raw raw(32767);begin select source_blob into l_blob from doom_dvl2_render_source for update;'
emit_blob
cat <<SQL
end;
/
declare l_count number;begin
  select count(*) into l_count from doom_dvl2_render_source
   where dbms_lob.getlength(source_blob)=source_bytes
     and lower(rawtohex(dbms_crypto.hash(
       source_blob,dbms_crypto.hash_sh256)))=source_sha;
  if l_count<>1 then
    raise_application_error(-20796,'DVL2 coordinator staging mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_DVL2_COORDINATOR_STAGING|PASS|source_bytes=$bytes|source_sha256=$sha|renderer=$renderer_kind');
end;
/
create mle env doom_dvl2_render_env imports(
  'doom_dvl2_engine' module doom_dvl2_simulation,
  '$renderer_alias' module $renderer_module,
  'doom_live_compositor' module $([[ "$unified" == YES ]] &&
    printf '%s' "$renderer_module" || printf doom_free_live_compositor));
create mle module doom_dvl2_render_coordinator language javascript using blob
  (select source_blob from doom_dvl2_render_source);
/
create function doom_fused_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateIwad(number)';
/
create function doom_fused_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadIwadChunk(number, Uint8Array)';
/
create function doom_fused_table_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateTablePack(number)';
/
create function doom_fused_table_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadTablePackChunk(number, Uint8Array)';
/
create function doom_fused_pack_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateRendererPack(number)';
/
create function doom_fused_pack_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadRendererPackChunk(number, Uint8Array)';
/
create function doom_fused_pack_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeRendererPack()';
/
create function doom_fused_wall_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateWallTextures(number)';
/
create function doom_fused_wall_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadWallTextureChunk(number, Uint8Array)';
/
create function doom_fused_wall_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeWallTextures()';
/
create function doom_fused_flat_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateFlatTextures(number)';
/
create function doom_fused_flat_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadFlatTextureChunk(number, Uint8Array)';
/
create function doom_fused_flat_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeFlatTextures()';
/
create function doom_fused_compositor_pack_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateCompositorPack(number)';
/
create function doom_fused_compositor_pack_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadCompositorPackChunk(number, Uint8Array)';
/
create function doom_fused_compositor_pack_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeCompositorPack()';
/
create function doom_fused_compositor_sprite_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateCompositorSprites(number)';
/
create function doom_fused_compositor_sprite_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadCompositorSpriteChunk(number, Uint8Array)';
/
create function doom_fused_compositor_sprite_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeCompositorSprites()';
/
create function doom_fused_compositor_ui_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateCompositorUi(number)';
/
create function doom_fused_compositor_ui_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadCompositorUiChunk(number, Uint8Array)';
/
create function doom_fused_compositor_ui_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeCompositorUi()';
/
create function doom_fused_set_range(p_start number,p_end number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'setColumnRange(number, number)';
/
create function doom_fused_sprite_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateSpriteTextures(number)';
/
create function doom_fused_sprite_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadSpriteTextureChunk(number, Uint8Array)';
/
create function doom_fused_sprite_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeSpriteTextures()';
/
create function doom_fused_ui_allocate(p_length number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'allocateUiTextures(number)';
/
create function doom_fused_ui_load(p_offset number,p_chunk raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadUiTextureChunk(number, Uint8Array)';
/
create function doom_fused_ui_finalize return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'finalizeUiTextures()';
/
create function doom_fused_init(p_active number,p_deathmatch number,p_skill number,p_episode number,p_map number)return varchar2 as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'initializeMultiplayerGame(number, number, number, number, number)';
/
create function doom_fused_origin_capture return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'captureOriginCheckpoint()';
/
create function doom_fused_origin_restore return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'restoreOriginCheckpoint()';
/
create function doom_fused_render_current(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'renderCurrentFrame(number)';
/
create function doom_fused_step_render(p_active number,p_mask number,p_commands raw,p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'stepAndRender(number, number, Uint8Array, number)';
/
create function doom_fused_step_render_static(p_active number,p_mask number,p_commands raw,p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'stepAndRenderStatic(number, number, Uint8Array, number)';
/
create function doom_fused_step_render_fast(p_active number,p_mask number,p_commands raw,p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'stepAndRenderFast(number, number, Uint8Array, number)';
/
create function doom_fused_step_commands(p_active number,p_mask number,p_commands raw,p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'stepAndGenerateCommands(number, number, Uint8Array, number)';
/
create function doom_fused_step_only(p_active number,p_mask number,p_commands raw)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'stepOnly(number, number, Uint8Array)';
/
create function doom_fused_render_temporal(p_player number,p_tic number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'renderConfirmedTemporalFrame(number, number)';
/
create function doom_fused_stage_load(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadCurrentDynamics(number)';
/
create function doom_fused_stage_walls return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'renderLoadedWalls()';
/
create function doom_fused_stage_geometry return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'renderLoadedGeometry()';
/
create function doom_fused_stage_prepare(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'prepareCurrentSnapshot(number)';
/
create function doom_fused_stage_import return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'loadPreparedDynamics()';
/
create function doom_fused_stage_render return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'renderPreparedFrame()';
/
create function doom_fused_frame_chunk(p_offset number,p_length number)return raw as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'frameChunk(number, number)';
/
create function doom_fused_publish(p_frame_id number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'publishPreparedFrame(number)';
/
create function doom_fused_publish_locator(p_frame_id number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'publishPreparedFrameLocator(number)';
/
create function doom_fused_batch_reset(p_capacity number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'resetPreparedLiveFrameBatch(number)';
/
create function doom_fused_batch_append(p_frame_id number,p_palette number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'appendPreparedLiveFrame(number, number)';
/
create function doom_fused_batch_publish(p_batch_id number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'publishPreparedLiveFrameBatchLocator(number)';
/
create function doom_fused_compose(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'composeCurrentFrame(number)';
/
create function doom_fused_compose_prepare(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'prepareCurrentComposition(number)';
/
create function doom_fused_compose_build(p_player number)return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'buildCurrentComposition(number)';
/
create function doom_fused_compose_export return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'exportCurrentComposition()';
/
create function doom_fused_compose_copy return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'copyCurrentCompositionBuffers()';
/
create function doom_fused_compose_sprites return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'composePreparedWorldSprites()';
/
create function doom_fused_compose_weapon return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'composePreparedWeapon()';
/
create function doom_fused_compose_status return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'composePreparedStatus()';
/
create function doom_fused_native_view_verify return number as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'verifyNativeViewContract()';
/
create procedure doom_fused_release as mle module doom_dvl2_render_coordinator env doom_dvl2_render_env signature 'release()';
/
commit;
SQL
