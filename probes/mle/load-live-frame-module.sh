#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
db_sql_client="${DOOMDB_DB_SQL_CLIENT:-$root/scripts/db_sql.sh}"
renderer="$root/artifacts/performance/pmle-live-frame-hud/renderer-c60a34dd81d6.js"
coordinator="${PMLE_LIVE_FRAME_COORDINATOR:-$root/artifacts/performance/pmle-live-frame-stage-split/coordinator-906f045eb2c5.mjs}"
world_pack="$root/artifacts/performance/pmle-live-frame-hud/world-pack-4f5fed82d21a.bin"
compositor_pack="$root/artifacts/performance/pmle-live-frame-hud/compositor-pack-e31962b3a177.bin"
wall_asset="$root/artifacts/performance/pmle-live-frame-hud/wall-assets-4e23605106fe.bin"
flat_asset="$root/artifacts/performance/pmle-live-frame-hud/flat-assets-bd6225c38111.bin"
sprite_asset="$root/artifacts/performance/pmle-live-frame-hud/sprite-assets-626e52a0ce5c.bin"
ui_asset="$root/artifacts/performance/pmle-live-frame-hud/ui-assets-8961a242c674.bin"
lock="${PMLE_LIVE_FRAME_LOCK:-$root/versions.lock}"
fold_width=2000
emit_only=0

if [[ "$lock" != "$root/versions.lock" &&
      "${PMLE_LIVE_FRAME_CANDIDATE:-NO}" != YES ]]; then
  printf '%s\n' \
    'candidate live-frame lock requires PMLE_LIVE_FRAME_CANDIDATE=YES' >&2
  exit 2
fi

case "${1:-}" in
  --emit-sql) emit_only=1;;
  '') ;;
  *) printf 'usage: %s [--emit-sql]\n' "$0" >&2;exit 2;;
esac
for file in "$renderer" "$coordinator" "$world_pack" "$compositor_pack" \
  "$wall_asset" "$flat_asset" "$sprite_asset" "$ui_asset" "$lock"; do
  [[ -s "$file" && ! -L "$file" ]] || {
    printf 'live-frame input is unavailable: %s\n' "$file" >&2;exit 2; }
done

IFS=$'\t' read -r \
  authority_bytes authority_sha \
  renderer_bytes renderer_sha coordinator_bytes coordinator_sha \
  world_bytes world_sha compositor_bytes compositor_sha \
  wall_bytes wall_sha flat_bytes flat_sha \
  sprite_bytes sprite_sha ui_bytes ui_sha < <(
  node - "$lock" <<'NODE'
import fs from 'node:fs';
const lock=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const live=lock.teaVM?.liveFrameRenderer;
if (!live) throw new Error('liveFrameRenderer pin is absent');
process.stdout.write(`${[
  live.authorityCandidateBytes,live.authorityCandidateSha256,
  live.outputBytes,live.outputSha256,
  live.coordinatorBytes,live.coordinatorSha256,
  live.worldPackBytes,live.worldPackSha256,
  live.compositorPackBytes,live.compositorPackSha256,
  live.wallAssetBytes,live.wallAssetSha256,
  live.flatAssetBytes,live.flatAssetSha256,
  live.spriteAssetBytes,live.spriteAssetSha256,
  live.uiAssetBytes,live.uiAssetSha256,
].join('\t')}\n`);
NODE
)

verify_file() {
  local file="$1" expected_bytes="$2" expected_sha="$3" actual_bytes actual_sha
  actual_bytes="$(wc -c <"$file" | tr -d '[:space:]')"
  actual_sha="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual_bytes" == "$expected_bytes" && "$actual_sha" == "$expected_sha" ]] || {
    printf 'live-frame pin mismatch: %s expected=%s/%s actual=%s/%s\n' \
      "$file" "$expected_bytes" "$expected_sha" "$actual_bytes" "$actual_sha" >&2
    exit 2
  }
}
verify_file "$renderer" "$renderer_bytes" "$renderer_sha"
verify_file "$coordinator" "$coordinator_bytes" "$coordinator_sha"
verify_file "$world_pack" "$world_bytes" "$world_sha"
verify_file "$compositor_pack" "$compositor_bytes" "$compositor_sha"
verify_file "$wall_asset" "$wall_bytes" "$wall_sha"
verify_file "$flat_asset" "$flat_bytes" "$flat_sha"
verify_file "$sprite_asset" "$sprite_bytes" "$sprite_sha"
verify_file "$ui_asset" "$ui_bytes" "$ui_sha"

emit_blob() {
  local file="$1" target="$2"
  base64 <"$file" | tr -d '\r\n' | fold -w "$fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf 'dbms_lob.writeappend(%s,utl_raw.length(l_raw),l_raw);\n' "$target"
    done
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767' \
    'set serveroutput on size unlimited'
  for object in \
    'procedure doom_mle_live_release' \
    'function doom_mle_live_frame_flush' \
    'function doom_mle_live_frame_prewarm' \
    'function doom_mle_live_publish_prepared_views' \
    'function doom_mle_live_prepare_views' \
    'function doom_mle_live_render_publish_views' \
    'function doom_mle_live_render_publish' \
    'function doom_mle_live_ui_finalize' \
    'function doom_mle_live_ui_load' \
    'function doom_mle_live_ui_allocate' \
    'function doom_mle_live_sprite_finalize' \
    'function doom_mle_live_sprite_load' \
    'function doom_mle_live_sprite_allocate' \
    'function doom_mle_live_flat_finalize' \
    'function doom_mle_live_flat_load' \
    'function doom_mle_live_flat_allocate' \
    'function doom_mle_live_wall_finalize' \
    'function doom_mle_live_wall_load' \
    'function doom_mle_live_wall_allocate' \
    'function doom_mle_live_compositor_pack_finalize' \
    'function doom_mle_live_compositor_pack_load' \
    'function doom_mle_live_compositor_pack_allocate' \
    'function doom_mle_live_world_pack_finalize' \
    'function doom_mle_live_world_pack_load' \
    'function doom_mle_live_world_pack_allocate' \
    'function doom_mle_live_memory' \
    'function doom_mle_live_world_chunk' \
    'function doom_mle_live_world_length' \
    'function doom_mle_live_restore_warm' \
    'function doom_mle_live_restore' \
    'function doom_mle_live_restore_load' \
    'function doom_mle_live_restore_allocate' \
    'function doom_mle_live_checkpoint_chunk' \
    'function doom_mle_live_checkpoint_length' \
    'function doom_mle_live_state' \
    'function doom_mle_live_canonical_state' \
    'function doom_mle_live_step' \
    'function doom_mle_live_init_game' \
    'function doom_mle_live_table_load' \
    'function doom_mle_live_table_allocate' \
    'function doom_mle_live_iwad_load' \
    'function doom_mle_live_iwad_allocate'; do
    printf "begin execute immediate 'drop %s';exception when others then if sqlcode<>-4043 then raise;end if;end;\n/\n" \
      "$object"
  done
  printf '%s\n' \
    "begin execute immediate 'drop mle module doom_mle_live_coordinator';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle env doom_mle_live_env';exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_mle_live_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    'delete from doom_mle_live_frame_source;' \
    "insert into doom_mle_live_frame_source values(1,$authority_bytes,'$authority_sha',empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),empty_blob(),$renderer_bytes,'$renderer_sha',$coordinator_bytes,'$coordinator_sha',$world_bytes,'$world_sha',$compositor_bytes,'$compositor_sha',$wall_bytes,'$wall_sha',$flat_bytes,'$flat_sha',$sprite_bytes,'$sprite_sha',$ui_bytes,'$ui_sha');" \
    'declare l_renderer blob;l_coordinator blob;l_world blob;l_compositor blob;l_wall blob;l_flat blob;l_sprite blob;l_ui blob;l_raw raw(32767);begin' \
    'select renderer_source,coordinator_source,world_pack,compositor_pack,wall_asset,flat_asset,sprite_asset,ui_asset' \
    'into l_renderer,l_coordinator,l_world,l_compositor,l_wall,l_flat,l_sprite,l_ui' \
    'from doom_mle_live_frame_source where artifact_id=1 for update;'
  emit_blob "$renderer" l_renderer
  emit_blob "$coordinator" l_coordinator
  emit_blob "$world_pack" l_world
  emit_blob "$compositor_pack" l_compositor
  emit_blob "$wall_asset" l_wall
  emit_blob "$flat_asset" l_flat
  emit_blob "$sprite_asset" l_sprite
  emit_blob "$ui_asset" l_ui
  printf '%s\n' \
    'end;' \
    '/' \
    'declare l_count number;begin' \
    'select count(*) into l_count from doom_teavm_sim_source' \
    "where dbms_lob.getlength(source_blob)=$authority_bytes" \
    "and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))='$authority_sha';" \
    "if l_count<>1 then raise_application_error(-20796,'live-frame authority source mismatch');end if;" \
    'select count(*) into l_count from doom_mle_live_frame_source' \
    'where artifact_id=1' \
    "and authority_bytes=$authority_bytes" \
    "and authority_sha256='$authority_sha'" \
    'and dbms_lob.getlength(renderer_source)=renderer_bytes' \
    'and dbms_lob.getlength(coordinator_source)=coordinator_bytes' \
    'and dbms_lob.getlength(world_pack)=world_pack_bytes' \
    'and dbms_lob.getlength(compositor_pack)=compositor_pack_bytes' \
    'and dbms_lob.getlength(wall_asset)=wall_asset_bytes' \
    'and dbms_lob.getlength(flat_asset)=flat_asset_bytes' \
    'and dbms_lob.getlength(sprite_asset)=sprite_asset_bytes' \
    'and dbms_lob.getlength(ui_asset)=ui_asset_bytes' \
    'and lower(rawtohex(dbms_crypto.hash(renderer_source,dbms_crypto.hash_sh256)))=renderer_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(coordinator_source,dbms_crypto.hash_sh256)))=coordinator_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(world_pack,dbms_crypto.hash_sh256)))=world_pack_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(compositor_pack,dbms_crypto.hash_sh256)))=compositor_pack_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(wall_asset,dbms_crypto.hash_sh256)))=wall_asset_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(flat_asset,dbms_crypto.hash_sh256)))=flat_asset_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(sprite_asset,dbms_crypto.hash_sh256)))=sprite_asset_sha256' \
    'and lower(rawtohex(dbms_crypto.hash(ui_asset,dbms_crypto.hash_sh256)))=ui_asset_sha256;' \
    "if l_count<>1 then raise_application_error(-20796,'live-frame source staging mismatch');end if;" \
    "dbms_output.put_line('PMLE_LIVE_FRAME_STAGING|PASS|authority_bytes=$authority_bytes|authority_sha256=$authority_sha|renderer_bytes=$renderer_bytes|renderer_sha256=$renderer_sha|coordinator_bytes=$coordinator_bytes|coordinator_sha256=$coordinator_sha');end;" \
    '/' \
    'create mle module doom_mle_live_renderer language javascript using blob' \
    '(select renderer_source from doom_mle_live_frame_source where artifact_id=1);' \
    '/' \
    "create mle env doom_mle_live_env imports('doom_dvl2_engine' module doom_teavm_simulation,'doom_live_renderer' module doom_mle_live_renderer,'doom_live_compositor' module doom_mle_live_renderer);" \
    'create mle module doom_mle_live_coordinator language javascript using blob' \
    '(select coordinator_source from doom_mle_live_frame_source where artifact_id=1);' \
    '/' \
    "create function doom_mle_live_iwad_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateIwad(number)';" \
    '/' \
    "create function doom_mle_live_iwad_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadIwadChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_table_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateTablePack(number)';" \
    '/' \
    "create function doom_mle_live_table_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadTablePackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_init_game(p_active number,p_deathmatch number,p_skill number,p_episode number,p_map number)return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" \
    '/' \
    "create function doom_mle_live_step(p_active number,p_mask number,p_commands raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'stepOnly(number, number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_canonical_state return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'canonicalState()';" \
    '/' \
    "create function doom_mle_live_state return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'currentState()';" \
    '/' \
    "create function doom_mle_live_checkpoint_length return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'checkpointLength()';" \
    '/' \
    "create function doom_mle_live_checkpoint_chunk(p_offset number,p_length number)return raw as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'checkpointChunk(number, number)';" \
    '/' \
    "create function doom_mle_live_restore_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateCheckpoint(number)';" \
    '/' \
    "create function doom_mle_live_restore_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadCheckpointChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_restore(p_tic number)return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'restoreCheckpoint(number)';" \
    '/' \
    "create function doom_mle_live_restore_warm(p_tic number)return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'restoreCheckpointWarm(number)';" \
    '/' \
    "create function doom_mle_live_world_length(p_player number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'presentationWorldSnapshotLength(number)';" \
    '/' \
    "create function doom_mle_live_world_chunk(p_offset number,p_length number)return raw as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'presentationWorldSnapshotChunk(number, number)';" \
    '/' \
    "create function doom_mle_live_memory return varchar2 as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'memoryDiagnostic()';" \
    '/' \
    "create function doom_mle_live_world_pack_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateRendererPack(number)';" \
    '/' \
    "create function doom_mle_live_world_pack_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadRendererPackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_world_pack_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeRendererPack()';" \
    '/' \
    "create function doom_mle_live_compositor_pack_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateCompositorPack(number)';" \
    '/' \
    "create function doom_mle_live_compositor_pack_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadCompositorPackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_compositor_pack_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeCompositorPack()';" \
    '/' \
    "create function doom_mle_live_wall_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateWallTextures(number)';" \
    '/' \
    "create function doom_mle_live_wall_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadWallTextureChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_wall_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeWallTextures()';" \
    '/' \
    "create function doom_mle_live_flat_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateFlatTextures(number)';" \
    '/' \
    "create function doom_mle_live_flat_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadFlatTextureChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_flat_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeFlatTextures()';" \
    '/' \
    "create function doom_mle_live_sprite_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateCompositorSprites(number)';" \
    '/' \
    "create function doom_mle_live_sprite_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadCompositorSpriteChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_sprite_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeCompositorSprites()';" \
    '/' \
    "create function doom_mle_live_ui_allocate(p_length number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'allocateCompositorUi(number)';" \
    '/' \
    "create function doom_mle_live_ui_load(p_offset number,p_chunk raw)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'loadCompositorUiChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_mle_live_ui_finalize return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'finalizeCompositorUi()';" \
    '/' \
    "create function doom_mle_live_render_publish(p_match varchar2,p_player number,p_epoch number,p_generation number,p_tic number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'renderAndPublishMatchFrame(string, number, number, number, number)';" \
    '/' \
    "create function doom_mle_live_render_publish_views(p_match varchar2,p_player_mask number,p_epoch number,p_generation number,p_tic number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'renderAndPublishMatchViews(string, number, number, number, number)';" \
    '/' \
    "create function doom_mle_live_prepare_views(p_match varchar2,p_player_mask number,p_epoch number,p_generation number,p_tic number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'prepareMatchViews(string, number, number, number, number)';" \
    '/' \
    "create function doom_mle_live_publish_prepared_views(p_match varchar2,p_player_mask number,p_epoch number,p_generation number,p_tic number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'publishPreparedMatchViews(string, number, number, number, number)';" \
    '/' \
    "create function doom_mle_live_frame_prewarm(p_iterations number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'prewarmCompleteRenderer(number)';" \
    '/' \
    "create function doom_mle_live_frame_flush(p_match varchar2,p_epoch number,p_generation number)return number as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'flushMatchLiveFrameBatches(string, number, number)';" \
    '/' \
    "create procedure doom_mle_live_release as mle module doom_mle_live_coordinator env doom_mle_live_env signature 'release()';" \
    '/' \
    'commit;'
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi
active_contexts="$("$db_sql_client" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_LIVE_CONTEXTS='||count(*) from doom_mle_warm_slot
where slot_status in('WARMING','READY','CLAIMED','RUNNING');
SQL
)"
active_contexts="$(awk -F= '/^ACTIVE_LIVE_CONTEXTS=/{print $2}' \
  <<<"$active_contexts" | tr -d '[:space:]')"
[[ "$active_contexts" == 0 ]] || {
  printf 'live-frame module deployment requires the retained pool parked; active contexts=%s\n' \
    "${active_contexts:-UNKNOWN}" >&2
  exit 1
}
emit_sql | "$db_sql_client" -
