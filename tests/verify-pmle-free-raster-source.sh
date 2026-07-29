#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe="$root/probes/mle"
source_file="$probe/free-raster-teavm/src/main/java/doomdb/mle/raster/FreeRasterKernel.java"
full_source="$probe/free-raster-teavm/src/main/java/doomdb/mle/raster/FullCommandRasterKernel.java"
install="$probe/install-free-raster-teavm.sh"
runner="$probe/run-oci-free-raster-teavm.sh"
benchmark="$probe/benchmark-oci-free-raster-teavm.sql"
full_install="$probe/install-full-command-raster-pack.sh"
full_runner="$probe/run-oci-full-command-raster.sh"
full_benchmark="$probe/benchmark-oci-full-command-raster.sql"
node_rank="$probe/rank-full-command-raster-node.mjs"
capture_patch="$probe/teavm-engine/0006-teavm-presentation-command-capture.patch"
capture_build="$probe/teavm-engine/build-presentation.sh"
capture_pom="$probe/teavm-engine/pom.xml"
capture_probe="$probe/teavm-engine/src/presentation-command-capture-engine/java/doomdb/mle/engine/PresentationCommandCaptureProbe.java"
capture_metrics="$probe/teavm-engine/src/presentation-command-capture/java/rr/drawfuns/FrameCommandMetrics.java"
capture_runner="$probe/teavm-engine/run-presentation-command-census.sh"
live_runner="$probe/teavm-engine/run-oci-live-command-raster.sh"
live_benchmark="$probe/teavm-engine/benchmark-oci-live-command-raster.sql"
live_bisection="$probe/teavm-engine/benchmark-oci-live-command-bisection.sql"
snapshot_authority="$probe/teavm-engine/src/main/java/doomdb/mle/engine/SimulationEngineReachabilityProbe.java"
snapshot_renderer="$probe/free-live-teavm/src/main/java/doomdb/mle/renderer/FreeLiveRendererReachabilityProbe.java"
snapshot_fixture_test="$probe/verify-free-live-snapshot-node.mjs"
snapshot_integration_test="$probe/verify-live-authority-renderer-node.mjs"
fixed_step_test="$probe/verify-free-live-fixed-step.mjs"
live_pack_builder="$probe/build-free-live-render-pack.mjs"
live_asset_builder="$probe/build-render-asset-blobs.mjs"
live_renderer_install="$probe/install-free-live-renderer-teavm.sh"
live_renderer_cleanup="$probe/cleanup-free-live-renderer-teavm.sql"
live_renderer_raster="$probe/benchmark-oci-free-live-renderer-teavm-raster.sql"
live_frame_extractor="$probe/extract-free-live-frame.mjs"
live_predeclaration="$root/artifacts/performance/pmle-free-live-frames/PREDECLARATION.md"

for input in "$source_file" "$full_source" "$install" "$runner" "$benchmark" \
  "$full_install" "$full_runner" "$full_benchmark" "$node_rank" \
  "$capture_patch" "$capture_build" "$capture_pom" "$capture_probe" "$capture_metrics" \
  "$capture_runner" "$live_runner" "$live_benchmark" "$live_bisection" \
  "$snapshot_authority" "$snapshot_renderer" "$snapshot_fixture_test" \
  "$snapshot_integration_test" "$fixed_step_test" "$live_pack_builder" \
  "$live_asset_builder" \
  "$live_renderer_install" \
  "$live_renderer_cleanup" "$live_renderer_raster" "$live_predeclaration" \
  "$live_frame_extractor" \
  "$probe/build-free-raster-teavm.sh" "$probe/cleanup-free-raster-teavm.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'free-raster verifier: missing input %s\n' "$input" >&2
    exit 1
  }
done

bash -n \
  "$probe/build-free-raster-teavm.sh" \
  "$install" \
  "$runner" \
  "$full_install" \
  "$full_runner" \
  "$live_runner"

require() {
  local pattern="$1" file="$2"
  grep -Fq -- "$pattern" "$file" || {
    printf 'free-raster verifier: missing %s in %s\n' "$pattern" "$file" >&2
    exit 1
  }
}

# Pin the selected exact bulk-reset/column-major shape.  Reintroducing the
# per-frame background loop or row-major source multiply invalidates the OCI
# rank even if a broad output checksum still happens to match.
require 'System.arraycopy(backgroundFrame, 0, frame, 0, PIXELS);' "$source_file"
require 'transposeReferencedColumns();' "$source_file"
require 'frame[output + pixel] = atlas[sourceBase + sourceY];' "$source_file"
if grep -Fq 'atlas[sourceBase + sourceY * width]' "$source_file"; then
  printf 'free-raster verifier: stale row-major hot path\n' >&2
  exit 1
fi

# Artifact loads are fail-closed in the database, and folded base64 must keep
# its final unterminated line.
require "dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)" "$install"
require 'while IFS= read -r piece || [[ -n "$piece" ]]; do' "$install"
require "raise_application_error(-20796,'small raster staging mismatch')" "$install"

# Evidence is immutable, exact frames are compared before timing, and cleanup
# proves both diagnostic objects and the pinned authority were restored.
require '[[ ! -e "$output" ]]' "$runner"
require 'PMLE_FREE_RASTER_EQUIVALENCE|PASS|' "$runner"
require '[[ "$(grep -c '\''^PMLE_FREE_RASTER_EQUIVALENCE|PASS|'\'' "$rank_log")" == 3 ]]' "$runner"
require "l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'" "$runner"
require 'PMLE_FREE_RASTER_POSTFLIGHT|PASS|diagnostic_objects=0' "$runner"
require 'utl_raw.compare(l_reference,l_candidate)<>0' "$benchmark"
require 'c_frames constant pls_integer:=500' "$benchmark"
require 'c_passes constant pls_integer:=12' "$benchmark"

# The promoted authentic viewport path resolves captured bytes once into
# primitive arrays. Reintroducing per-frame command decoding forfeits the
# measured 59 FPS result even when the eventual pixels remain exact.
require 'resolveCommand(command++, commandAt);' "$full_source"
require 'int command = commandStarts[frameIndex];' "$full_source"
require 'frame[output] = pack[source + spot];' "$full_source"
require 'output += FRAME_HEIGHT;' "$full_source"
require 'throw new IllegalStateException(' "$full_source"
require '"fuzz command requires the separately gated fuzz path"' "$full_source"

# Pack and module staging are byte-length/SHA fail-closed, and exact viewport
# evidence precedes both per-call and retained timing.
require "dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)" "$full_install"
require 'while IFS= read -r piece || [[ -n "$piece" ]]; do' "$full_install"
require "raise_application_error(-20796,'full-command staging mismatch')" "$full_install"
require 'PMLE_FULL_COMMAND_RASTER_NODE|PASS|frames=${frames}' "$node_rank"
require 'viewport_exact=${frames}' "$node_rank"
require 'full_frame_exact=${frames}' "$node_rank"
require 'PMLE_FULL_COMMAND_EQUIVALENCE|PASS|' "$full_benchmark"
require 'c_frames constant pls_integer:=192' "$full_benchmark"
require 'c_passes constant pls_integer:=12' "$full_benchmark"
require 'PMLE_FULL_COMMAND_VERDICT|' "$full_runner"
require 'final_two_worst_p95_ms=%s' "$full_runner"
require 'hud=CAPTURED_EXACT_NOT_LIVE_GENERATED' "$full_runner"
require 'PMLE_FULL_COMMAND_POSTFLIGHT|PASS|diagnostic_objects=0' "$full_runner"

# Capture reachability is a candidate-only overlay. The shipping authority
# sources must not import the retained command/asset registry.
require '0006-teavm-presentation-command-capture.patch' "$capture_build"
require 'presentation-command-capture-engine/java' "$capture_pom"
require 'DOOMDB_MOCHA_EXTRA_ADAPTER_SOURCE=' "$capture_build"
require 'doomdbEnableFrameCommandMetrics();' "$capture_patch"
require 'FrameCommandMetrics.enable();' "$capture_patch"
require 'class PresentationCommandCaptureProbe' "$capture_probe"
require 'private static final int COMMAND_BYTES = 28;' "$capture_metrics"
require "header.writeUInt32LE(4, 4);" \
  "$probe/teavm-engine/run-presentation-node.mjs"
require "version=4|frames=192" "$capture_runner"

# The integrated path must intercept only final viewport writes, retain
# primitive commands and prelit assets, and expose a complete database-authored
# wire frame. Node exactness precedes OCI route/peak timing.
require 'if (!FrameCommandMetrics.isCaptureOnly()) {' \
  "$probe/teavm-engine/src/presentation-command-capture/java/rr/drawfuns/MetricColumnFunction.java"
require 'if (!FrameCommandMetrics.isCaptureOnly()) {' \
  "$probe/teavm-engine/src/presentation-command-capture/java/rr/drawfuns/MetricSpanFunction.java"
require 'private static final int ASSET_HASH_SIZE = 32768;' "$capture_metrics"
require 'capturedFrame[x * VIEW_HEIGHT + y]' "$capture_metrics"
require '"live fuzz raster requires its separately gated path"' "$capture_metrics"
require 'renderCapturedPlayerFrameLength' "$capture_probe"
require 'capturedPlayerFrameRowMajorChunk' "$capture_probe"
require 'PMLE_PRESENTATION_LIVE_CAPTURE|PASS|frames=${liveCaptureExactFrames}' \
  "$probe/teavm-engine/run-presentation-node.mjs"
require '## Live integrated command generation and full-frame raster' \
  "$live_predeclaration"
require 'pipeline p95 `<=33.333 ms`' "$live_predeclaration"
require 'PMLE_LIVE_COMMAND_EQUIVALENCE|PASS|' "$live_benchmark"
require "run_window('PEAK_AWAKE',100);" "$live_benchmark"
require "run_window('QUIET_ROUTE',1200);" "$live_benchmark"
require 'PMLE_LIVE_COMMAND_VERDICT|' "$live_runner"
require 'full_frame_exact_node=192|full_frame_exact_oci=6' "$live_runner"
require 'PMLE_LIVE_COMMAND_POSTFLIGHT|PASS|' "$live_runner"

# The specialized live renderer consumes bounded authoritative state rather
# than a prerecorded pose index. Fixture-equivalence and a changing two-player
# authority stream are both executable Node gates.
require 'public static Uint8Array presentationPlayerSnapshot(int playerSlot)' \
  "$snapshot_authority"
require 'public static int presentationWorldSnapshotLength(int playerSlot)' \
  "$snapshot_authority"
require 'DVL2 header/player: 208 bytes' "$snapshot_authority"
require 'sideOffset + engine.levelLoader.sides.length * 8' \
  "$snapshot_authority"
require 'engine.textureManager.getFlatTranslation(sector.floorpic)' \
  "$snapshot_authority"
require 'presentationWorldSnapshotChunk(worldLength, 1)' \
  "$probe/teavm-engine/run-presentation-node.mjs"
require 'pov0_world_unique=${worldSnapshotHashes[0].size}' \
  "$probe/teavm-engine/run-presentation-node.mjs"
require 'snapshot.getLength() != 32' "$snapshot_renderer"
require 'return renderView(' "$snapshot_renderer"
require 'PMLE_FREE_LIVE_SNAPSHOT_NODE|PASS' "$snapshot_fixture_test"
require 'PMLE_LIVE_AUTHORITY_RENDERER_NODE|PASS' "$snapshot_integration_test"
require 'renderPlayerSnapshotGeometry(snapshot)' "$snapshot_integration_test"
require 'PMLE_LIVE_COMMAND_BISECTION|DIAGNOSTIC_NOT_GATE' "$live_bisection"

# Authentic floors/ceilings are IWAD-derived, prelit once, and rendered with
# Doom's affine row-span shape. Full-frame timing may not silently fall back
# to the old solid-color background or per-pixel perspective divisions.
require 'pack.writeUInt32LE(7, 4);' "$live_pack_builder"
require 'offsets.sectorFloorAsset' "$live_pack_builder"
require 'offsets.ssectorSector' "$live_pack_builder"
require 'offsets.spriteLookupAsset' "$live_pack_builder"
require 'offsets.uiDigits' "$live_pack_builder"
require 'offsets.uiFaceStraight' "$live_pack_builder"
require 'offsets.uiMainMenuItems' "$live_pack_builder"
require 'offsets.runtimeWallToAsset' "$live_pack_builder"
require 'offsets.runtimeFlatToAsset' "$live_pack_builder"
require 'offsets.lineRightSide' "$live_pack_builder"
require "sprite_patch', 'ui_patch'" "$live_asset_builder"
require 'public static int renderWorldSnapshot(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'drawWorldSprites(snapshot, stagedMobjOffset, stagedMobjCount);' \
  "$snapshot_renderer"
require 'public static int renderWorldGeometryStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'public static int loadWorldDynamicsStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'public static int renderLoadedWorldGeometryStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'public static int renderWorldSpritesStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'public static int renderWeaponStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'public static int renderStatusStage(Uint8Array snapshot)' \
  "$snapshot_renderer"
require 'drawPlayerSprites(snapshot);' "$snapshot_renderer"
require 'drawStatusBar(snapshot);' "$snapshot_renderer"
require 'dynamicSideMiddle[side]' "$snapshot_renderer"
require 'wallDepth[x * VIEW_HEIGHT + y]' "$snapshot_renderer"
require 'wallDepth[base + y] = Math.min(wallDepth[base + y], depth);' \
  "$snapshot_renderer"
require 'public static int renderTitleFrame()' "$snapshot_renderer"
require 'public static int renderMenuFrame(int page)' "$snapshot_renderer"
require 'public static int renderMenuSelectionFrame(' "$snapshot_renderer"
require 'public static int renderScreenFrame(int screen)' "$snapshot_renderer"
require 'face = uiFaceStraight[pain * 3 + (tic / 17) % 3];' \
  "$snapshot_renderer"
require 'public static int finalizeFlatTextures()' "$snapshot_renderer"
require 'litTextures[bank + base + sourceY * width + textureX]' \
  "$snapshot_renderer"
require 'int fractionStep = 8388608 / wallHeight;' "$snapshot_renderer"
require 'fraction += fractionStep;' "$snapshot_renderer"
require 'private static final int LIVE_RENDER_WIDTH = 160;' "$snapshot_renderer"
require 'pixelScale = WIDTH / activeWidth;' "$snapshot_renderer"
require 'frame[outputAt + FRAME_HEIGHT + output] = pixel;' \
  "$snapshot_renderer"
require 'PMLE_FREE_LIVE_FIXED_STEP|PASS' "$fixed_step_test"
require 'private static void drawPlaneBackground(' "$snapshot_renderer"
require 'private static void drawRecordedPlanes(' "$snapshot_renderer"
require 'private static void recordPlaneRange(' "$snapshot_renderer"
require 'spanStart[top++] = x;' "$snapshot_renderer"
require 'int source = ((worldY >> 10) & 4032)' "$snapshot_renderer"
require '+ ((worldX >> 16) & 63);' "$snapshot_renderer"
require 'output += pixelScale * FRAME_HEIGHT;' "$snapshot_renderer"
require 'select flat_blob,flat_bytes,flat_sha' "$live_renderer_raster"
require 'PMLE_FREE_LIVE_FRAME_CAPTURE|PASS|pose=750|bytes=64000' \
  "$live_renderer_raster"
require 'incomplete frame capture:' "$live_frame_extractor"
require 'incomplete palette:' "$live_frame_extractor"
require 'doom_free_gen_flat_finalize' "$live_renderer_install"
require 'doom_free_gen_sprite_finalize' "$live_renderer_install"
require 'doom_free_gen_ui_finalize' "$live_renderer_install"
require 'doom_free_gen_world' "$live_renderer_install"
require 'doom_free_gen_world_geometry' "$live_renderer_install"
require 'doom_free_gen_load_dynamics' "$live_renderer_install"
require 'doom_free_gen_loaded_geometry' "$live_renderer_install"
require 'doom_free_gen_world_sprites' "$live_renderer_install"
require 'doom_free_gen_weapon' "$live_renderer_install"
require 'doom_free_gen_status' "$live_renderer_install"
require 'doom_free_gen_menu_select' "$live_renderer_install"
require 'drop function doom_free_gen_flat_finalize' "$live_renderer_cleanup"
require 'drop function doom_free_gen_world' "$live_renderer_cleanup"
require 'drop function doom_free_gen_world_geometry' "$live_renderer_cleanup"
require 'drop function doom_free_gen_load_dynamics' "$live_renderer_cleanup"
require 'drop function doom_free_gen_loaded_geometry' "$live_renderer_cleanup"
require 'drop function doom_free_gen_world_sprites' "$live_renderer_cleanup"
require 'drop function doom_free_gen_weapon' "$live_renderer_cleanup"
require 'drop function doom_free_gen_status' "$live_renderer_cleanup"
if grep -Fq 'FrameCommandMetrics' \
  "$snapshot_authority"; then
  printf 'free-raster verifier: capture state reached shipping authority source\n' >&2
  exit 1
fi

printf '%s\n' 'PMLE_FREE_RASTER_SOURCE|PASS'
