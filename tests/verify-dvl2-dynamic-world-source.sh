#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENGINE=$ROOT/probes/mle/teavm-engine/src/main/java/doomdb/mle/engine/SimulationEngineReachabilityProbe.java
COORDINATOR=$ROOT/probes/mle/dvl2-world-raster-coordinator.mjs
GENERATOR=$ROOT/probes/mle/free-live-teavm/build-world-raster-source.mjs
COMPOSITOR=$ROOT/probes/mle/free-live-teavm/build-compositor-source.mjs
BASE_RENDERER=$ROOT/probes/mle/free-live-teavm/src/main/java/doomdb/mle/renderer/FreeLiveRendererReachabilityProbe.java
PACK_BUILD=$ROOT/probes/mle/build-free-live-world-raster-teavm.sh
UNIFIED_BUILD=$ROOT/probes/mle/build-free-live-unified-teavm.sh
UNIFIED_SOURCE=$ROOT/probes/mle/free-live-teavm/build-unified-source.mjs
NODE_GATE=$ROOT/probes/mle/verify-dvl2-dynamic-world-node.mjs
COMPACT_ROUTE_GATE=$ROOT/probes/mle/verify-compact-partial-depth-route-node.mjs

fail() {
  printf 'FAIL DVL2-DYNAMIC-WORLD-SOURCE: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'presentationWorldGeometryAndSidesSnapshotLength(' "$ENGINE" &&
  grep -Fq 'buildPresentationWorldSnapshot(playerSlot, true, true, false, false)' \
    "$ENGINE" ||
  fail 'authority does not export sectors+sidedefs without duplicate mobjs'
grep -Fq 'presentationWorldGeometryDeltaSnapshotLength(' "$ENGINE" &&
  grep -Fq 'presentationDirtySides[dirtySideCount++] = sideIndex' "$ENGINE" &&
  grep -Fq 'presentationDirtySectors[dirtySectorCount++] = sectorIndex' \
    "$ENGINE" &&
  grep -Fq 'presentationSectorFloor[sectorIndex]' "$ENGINE" &&
  grep -Fq 'presentationSectorCeilingAsset[sectorIndex]' "$ENGINE" &&
  grep -Fq 'boolean animationBoundary = engine.leveltime % 8 == 0' "$ENGINE" &&
  grep -Fq 'rawChanged || animationBoundary' "$ENGINE" &&
  grep -Fq 'getTextureTranslation(side.midtexture)' "$ENGINE" &&
  grep -Fq 'textureOffset != presentationSideTextureOffset[sideIndex]' \
    "$ENGINE" &&
  grep -Fq 'putPresentationI32(' "$ENGINE" &&
  grep -Fq 'offset + 10, presentationSideTextureOffset[sideIndex]' "$ENGINE" &&
  grep -Fq 'offset + 14, presentationSideRowOffset[sideIndex]' "$ENGINE" &&
  grep -Fq 'putPresentationI16(offset, sideIndex)' "$ENGINE" ||
  fail 'authority lacks exact translated dirty-sidedef tracking'
grep -Fq 'int presentationDirectionX = 0' "$ENGINE" &&
  grep -Fq 'presentationDirectionX = Tables.finecosine[angle] >> 8' "$ENGINE" &&
  grep -Fq 'presentationDirectionY = Tables.finesine[angle] >> 8' "$ENGINE" &&
  grep -Fq 'presentationDirectionX, presentationDirectionY' "$ENGINE" &&
  test "$(grep -Fc \
      '((int) mobj.flags & p.mobj_t.MF_NOSECTOR) != 0' "$ENGINE")" -eq 2 &&
  grep -Fq 'putPresentationI32(offset + 12, (int) mobj.angle >>> 16)' \
    "$ENGINE" &&
  grep -Fq \
    'int angle = ((int) player.mo.angle >>> Tables.ANGLETOFINESHIFT)' \
    "$ENGINE" &&
  ! grep -Fq '(mobj.angle >>> 16)' "$ENGINE" &&
  ! grep -Fq '(mobj.flags & p.mobj_t.MF_NOSECTOR)' "$ENGINE" &&
  ! sed -n '/private static boolean presentationMobjCandidate(/,/^  }/p' \
      "$ENGINE" | grep -Fq 'viewer.angle' ||
  fail 'compositor culling recomputes the invariant view direction per mobj'
  grep -Fq 'presentationWorldGeometryDeltaSnapshotLength(playerSlot)' \
    "$COORDINATOR" &&
  grep -Fq 'presentationWorldSnapshotNativeByRef()' "$COORDINATOR" &&
  grep -Fq 'length > 16 * 1024 * 1024' "$COORDINATOR" &&
  ! grep -Fq 'retainedSidesInitialized' "$COORDINATOR" ||
  fail 'coordinator does not consume the authoritative native world snapshot'
if grep -Fq 'presentationPlayerSnapshot(playerSlot)' "$COORDINATOR"; then
  fail 'camera-only DVP4 snapshot path returned to the live world coordinator'
fi
grep -Fq 'u32(4) != 5' "$GENERATOR" &&
  grep -Fq '0x314d4c44' "$GENERATOR" &&
  grep -Fq 'dynamicSideMiddle' "$GENERATOR" &&
  grep -Fq 'magic == 0x334c5644' "$GENERATOR" &&
  grep -Fq 'magic == 0x364c5644' "$GENERATOR" &&
  grep -Fq 'dirty * 18' "$GENERATOR" &&
  grep -Fq '"invalid DVL6 sector index"' "$GENERATOR" &&
  grep -Fq 'dynamicSideTextureOffset[side]' "$GENERATOR" &&
  grep -Fq 'dynamicSideRowOffset[side]' "$GENERATOR" &&
  grep -Fq '"invalid DVL6 side index"' "$GENERATOR" &&
  grep -Fq 'liveDynamicsActive = world' "$GENERATOR" &&
  grep -Fq 'clearRetainedView();' "$GENERATOR" &&
  grep -Fq "'single-column-interpreted-raster'" "$GENERATOR" &&
  grep -Fq '18,' "$GENERATOR" &&
  grep -Fq 'int scale = WIDTH / LIVE_RENDER_WIDTH;' "$GENERATOR" &&
  grep -Fq 'int source = column * scale * FRAME_HEIGHT;' "$GENERATOR" &&
  grep -Fq 'for (int copy = 1; copy < scale; copy++)' "$GENERATOR" &&
  grep -Fq \
    'frame, source, frame, source + copy * FRAME_HEIGHT, FRAME_HEIGHT' \
    "$GENERATOR" &&
  grep -Fq \
    'int source = (LIVE_RENDER_WIDTH - 1) * scale * FRAME_HEIGHT;' \
    "$GENERATOR" &&
  grep -Fq \
    'for (int column = LIVE_RENDER_WIDTH * scale; column < WIDTH; column++)' \
    "$GENERATOR" &&
  grep -Fq 'frame, source, frame, column * FRAME_HEIGHT, FRAME_HEIGHT' \
    "$GENERATOR" &&
  grep -Fq "'partial-wall-depth-fill'" "$GENERATOR" &&
  grep -Fq 'java.util.Arrays.fill(wallDepth, Double.POSITIVE_INFINITY)' \
    "$GENERATOR" &&
  grep -Fq 'wallDepthRangeStart[wallDepthRangeCount] = start' "$GENERATOR" &&
  grep -Fq 'wallDepthRangeEnd[wallDepthRangeCount] = end' "$GENERATOR" &&
  grep -Fq 'java.util.Arrays.fill(wallDepth, start, end, depth)' "$GENERATOR" &&
  grep -Fq 'yOffset, wallDistance, false);' "$GENERATOR" &&
  test "$(grep -Fc 'wallDistance, true);' "$GENERATOR")" -eq 2 &&
  grep -Fq "'exact-light-map-shift'" "$GENERATOR" &&
  grep -Fq 'return (255 - (sectorLight[sector] & 255)) >>> 3;' \
    "$GENERATOR" &&
  grep -Fq 'lightBankCount = 32' "$GENERATOR" ||
  fail 'world generator lacks dynamic mappings, deterministic clear, or lights'
grep -Fq 'build-world-live-pack.mjs' "$PACK_BUILD" &&
  grep -Fq 'version=5|dynamics=sectors+sidedefs' "$PACK_BUILD" ||
  fail 'world pack build is not pinned to the DLM1 dynamic extension'
if grep -Fq 'cp "$base_pack" "$pack"' "$PACK_BUILD"; then
  fail 'static v4 pack can silently replace the dynamic live pack'
fi
grep -Fq 'buildBrightSpriteRuns();' "$COMPOSITOR" &&
  grep -Fq 'buildUiRuns();' "$BASE_RENDERER" &&
  grep -Fq '"UI run mismatch at "' "$BASE_RENDERER" &&
  grep -Fq 'uiAssetRunStart[asset]' "$BASE_RENDERER" &&
  grep -Fq "'compact-mobj-record-size'" "$COMPOSITOR" &&
  grep -Fq "'compact-mobj-ordered-record-size'" "$COMPOSITOR" &&
  grep -Fq 'worldSpriteOrder[index] * 24' "$COMPOSITOR" &&
  grep -Fq 'System.arraycopy(' "$COMPOSITOR" &&
  grep -Fq '"bright sprite run mismatch at "' "$COMPOSITOR" &&
  grep -Fq 'statusChangeMask(Uint8Array snapshot)' "$COMPOSITOR" &&
  grep -Fq 'int[] lastStatusState = new int[9]' "$COMPOSITOR" &&
  grep -Fq 'public static int resetPresentationState()' "$COMPOSITOR" &&
  grep -Fq 'statusBarInitialized = false;' "$COMPOSITOR" &&
  grep -Fq 'cardsValue != lastStatusState[8]' "$COMPOSITOR" &&
  grep -Fq "'widget-specific-status-restore'" "$COMPOSITOR" &&
  grep -Fq 'if ((statusChanges & 1) != 0)' "$COMPOSITOR" &&
  grep -Fq 'if ((statusChanges & 16) != 0)' "$COMPOSITOR" &&
  ! grep -Fq 'lastStatusSignature' "$COMPOSITOR" ||
  fail 'compositor lacks verified bright runs or exact retained-HUD invalidation'
grep -Fq 'PMLE_FREE_LIVE_OPTIMIZATION:-ADVANCED' "$UNIFIED_BUILD" &&
  grep -Fq '[[ "$optimization" == ADVANCED || "$optimization" == FULL ]]' \
    "$UNIFIED_BUILD" &&
  grep -Fq -- '-Dteavm.optimizationLevel="$optimization"' "$UNIFIED_BUILD" ||
  fail 'unified build no longer pins the measured ADVANCED/FULL optimization surface'
grep -Fq "'live-wall-pixel-direct-dispatch'" "$UNIFIED_SOURCE" &&
  grep -Fq "'live-raster-counter-updates'" "$UNIFIED_SOURCE" &&
  grep -Fq "'live-render-view-constants'" "$UNIFIED_SOURCE" &&
  grep -Fq "'live-record-plane-ranges'" "$UNIFIED_SOURCE" &&
  grep -Fq "'live-render-view-tail'" "$UNIFIED_SOURCE" &&
  grep -Fq "'live-compact-partial-depth-fields'" "$UNIFIED_SOURCE" &&
  grep -Fq 'partialDepthHead[screenX] = range' "$UNIFIED_SOURCE" &&
  grep -Fq "'live-compositor-compact-partial-depth-test'" "$UNIFIED_SOURCE" &&
  grep -Fq 'range = partialDepthNext[range]' "$UNIFIED_SOURCE" &&
  grep -Fq 'if (encoded == 0) continue;' "$UNIFIED_SOURCE" &&
  grep -Fq "'live-entry-compact-partial-depth-diagnostic'" "$UNIFIED_SOURCE" ||
  fail 'unified source no longer specializes the production-only raster path'
grep -Fq 'live_raster_dead_graph' "$UNIFIED_BUILD" &&
  grep -Fq 'wall command buffer overflow|resolved wall command buffer overflow|native wall tape overflow|rasterPixelWrites' \
    "$UNIFIED_BUILD" &&
  grep -Fq 'PMLE_FREE_LIVE_LIVE_RASTER_SPECIALIZATION|PASS' "$UNIFIED_BUILD" ||
  fail 'unified build no longer rejects unreachable raster diagnostic graphs'
grep -Fq 'PMLE_DVL2_DYNAMIC_WORLD_NODE|PASS' "$NODE_GATE" &&
  grep -Fq 'dirty_initial_bytes=' "$NODE_GATE" &&
  grep -Fq 'dirty_steady_bytes=' "$NODE_GATE" &&
  grep -Fq 'animation_dirty_sides=' "$NODE_GATE" &&
  grep -Fq 'animation_offset_sides=' "$NODE_GATE" &&
  grep -Fq 'scrolling_map=E' "$NODE_GATE" &&
  grep -Fq 'no live IWAD scrolling wall reached the DVL6 offset delta' \
    "$NODE_GATE" &&
  grep -Fq 'switch_tic=' "$NODE_GATE" &&
  grep -Fq 'accepted E1M1 route did not prove a live DVL6 switch texture delta' \
    "$NODE_GATE" &&
  grep -Fq 'dirty_offsets_sha256=' "$NODE_GATE" &&
  grep -Fq 'DVL6 animation-boundary dirty count is not exact' "$NODE_GATE" &&
  grep -Fq 'DVL6 initial sector mismatch' "$NODE_GATE" &&
  grep -Fq 'dirtySidesSha !== sidesSha' "$NODE_GATE" &&
  grep -Fq 'world_sprite_record_one_exact=YES' "$NODE_GATE" &&
  grep -Fq 'partial_wall_depth_pixels_max=' "$NODE_GATE" &&
  grep -Fq 'accepted dynamic route did not exercise partial-wall depth' \
    "$NODE_GATE" &&
  grep -Fq 'DVC4 record-one sprite addressing mismatch' "$NODE_GATE" &&
  grep -Fq 'status_widget_masks_exact=YES' "$NODE_GATE" &&
  grep -Fq 'retained presentation reset did not rebuild status pixels' \
    "$NODE_GATE" &&
  grep -Fq 'retained status ${name} widget did not restore exactly' \
    "$NODE_GATE" &&
  grep -Fq 'coarse horizontal expansion mismatch' "$NODE_GATE" &&
  grep -Fq 'coarse horizontal tail mismatch' "$NODE_GATE" &&
  grep -Fq 'single-column pixel-equivalence mismatch' "$NODE_GATE" &&
  grep -Fq '42cab1d280283be5e18ef9f7ca3eb9bc610341aff7ccdda3df10256cacfc5a8c' \
    "$NODE_GATE" &&
  grep -Fq 'restore_exact=YES' "$NODE_GATE" ||
  fail 'dynamic mutation/restore pixel gate is absent'
test -x "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'renderer-1f0bbaa10ce5.js' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'mle-live-deathmatch-2026-07-23.json' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'fixture.tics !== 5250' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'composeWorldSpritesStage(compositorSnapshot)' \
    "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'composeWeaponStage(compositorSnapshot)' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'composeStatusStage(compositorSnapshot)' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'if (!beforeBuffer.equals(afterBuffer))' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'PMLE_COMPACT_PARTIAL_DEPTH_ROUTE|PASS' "$COMPACT_ROUTE_GATE" &&
  grep -Fq 'stages=world,sprites,weapon,status' "$COMPACT_ROUTE_GATE" ||
  fail 'full-frame compact partial-depth route equivalence gate is absent'

printf '%s\n' 'PASS DVL2-DYNAMIC-WORLD-SOURCE'
