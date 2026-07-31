#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$ROOT/tests/verify-production-drop-inventory.mjs"
node "$ROOT/tests/verify-pmle-checkpoint-cadence.mjs"
node "$ROOT/tests/verify-input-repeat-recovery.mjs"
sh "$ROOT/tests/verify-pmle-wasm2js-source.sh"
sh "$ROOT/tests/verify-dvl2-dynamic-world-source.sh"
INSTALL=$ROOT/probes/mle/install.sql
BENCHMARK=$ROOT/probes/mle/benchmark.sql
RUNNER=$ROOT/probes/mle/run.sh
CLEANUP=$ROOT/probes/mle/cleanup.sql
NATIVE_INSTALL=$ROOT/probes/mle/native-install.sql
NATIVE_BENCHMARK=$ROOT/probes/mle/native-benchmark.sql
NATIVE_CLEANUP=$ROOT/probes/mle/native-cleanup.sql
HYBRID_INSTALL=$ROOT/probes/mle/hybrid-install.sql
HYBRID_BENCHMARK=$ROOT/probes/mle/hybrid-benchmark.sql
HYBRID_CLEANUP=$ROOT/probes/mle/hybrid-cleanup.sql
COMMAND_BENCHMARK=$ROOT/probes/mle/command-benchmark.sql
BIND_INSTALL=$ROOT/probes/mle/bind-install.sql
BIND_BENCHMARK=$ROOT/probes/mle/bind-benchmark.sql
BIND_CLEANUP=$ROOT/probes/mle/bind-cleanup.sql
ADB_INSTALL=$ROOT/probes/mle/adb-install.sql
ADB_BENCHMARK=$ROOT/probes/mle/adb-benchmark.sql
ADB_CLEANUP=$ROOT/probes/mle/adb-cleanup.sql
ADB_RUNNER=$ROOT/probes/mle/run-adb.sh
TEAVM_SIM_LOADER=$ROOT/probes/mle/teavm-engine/load-mle-module.sh
TEAVM_TIC0_BUILDER=$ROOT/probes/mle/teavm-engine/build-tic0-checkpoint-bank.mjs
TEAVM_TIC0_LOADER=$ROOT/probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh
TEAVM_SLICE_LOADER=$ROOT/probes/mle/teavm/deploy.sh
TEAVM_SIM_CLEANUP=$ROOT/probes/mle/teavm-engine/cleanup-mle.sql
TEAVM_LEDGER=$ROOT/probes/mle/teavm-engine/build-ledger-differential.mjs
TEAVM_LEDGER_PROGRESS_AUDIT=$ROOT/probes/mle/teavm-engine/compare-ledger-progress.mjs
TEAVM_LIVE_FRAME_REPRODUCIBILITY=$ROOT/probes/mle/teavm-engine/run-live-frame-authority-reproducibility.sh
TEAVM_LEDGER_COMPONENTS=$ROOT/probes/mle/teavm-engine/build-ledger-component-profile.mjs
TEAVM_LEDGER_COMPONENT_RUNNER=$ROOT/probes/mle/teavm-engine/run-ledger-component-ab.sh
TEAVM_LEDGER_COMPONENT_EXTRACTOR=$ROOT/probes/mle/teavm-engine/extract-ledger-component-digest.sh
TEAVM_CANONICAL_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-canonical-state.sql
TEAVM_RECOVERY=$ROOT/probes/mle/teavm-engine/recovery-mle.sql
TEAVM_MULTIPLAYER=$ROOT/probes/mle/teavm-engine/multiplayer-mle.sql
TEAVM_MULTI_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-multiplayer-mle.sql
TEAVM_MULTI_RECOVERY=$ROOT/probes/mle/teavm-engine/recovery-multiplayer-mle.sql
TEAVM_MULTI_SOAK=$ROOT/probes/mle/teavm-engine/soak-multiplayer-mle.sql
TEAVM_MULTI_SOAK_RUNNER=$ROOT/probes/mle/teavm-engine/run-multiplayer-soak.sh
TEAVM_COOP=$ROOT/probes/mle/teavm-engine/build-coop-differential.mjs
TEAVM_MEMBERSHIP_DIFF=$ROOT/probes/mle/teavm-engine/membership-recovery-differential.sql
TEAVM_BUILD=$ROOT/probes/mle/teavm-engine/build-simulation.sh
TEAVM_PRESENTATION_BUILD=$ROOT/probes/mle/teavm-engine/build-presentation.sh
TEAVM_DECPS_PATCH=$ROOT/probes/mle/teavm-engine/0006-teavm-authority-no-blocking-wait.patch
TEAVM_DECPS_RUNNER=$ROOT/probes/mle/teavm-engine/run-decps-rank-mle.sh
TEAVM_DECPS_PARITY=$ROOT/probes/mle/teavm-engine/run-javascript-candidate-parity.mjs
TEAVM_DECPS_GATES=$ROOT/probes/mle/teavm-engine/run-decps-promotion-gates.sh
TEAVM_LIVE_FRAME_GATES=$ROOT/probes/mle/teavm-engine/run-live-frame-authority-differentials.sh
TEAVM_DECPS_LEDGER=$ROOT/probes/mle/teavm-engine/run-decps-ledger.sh
TEAVM_DECPS_LEDGER_POSTFLIGHT=$ROOT/probes/mle/teavm-engine/attest-decps-ledger-postflight.sh
TEAVM_DECPS_READINESS=$ROOT/probes/mle/teavm-engine/check-decps-promotion-readiness.mjs
TEAVM_DECPS_REPRODUCIBILITY=$ROOT/probes/mle/teavm-engine/run-decps-reproducibility.sh
TEAVM_DECPS_PROMOTION=$ROOT/probes/mle/teavm-engine/promote-decps-authority.mjs
TEAVM_DECPS_DEPLOY=$ROOT/probes/mle/teavm-engine/deploy-decps-authority.sh
TEAVM_DASHBOARD_STATUS=$ROOT/scripts/build-mle-dashboard-status.mjs
TEAVM_DEPLOYMENT_STATE=$ROOT/scripts/set-decps-deployment-state.mjs
TEAVM_LIFECYCLE_MANIFEST=$ROOT/scripts/build-decps-lifecycle-manifest.mjs
TEAVM_DECPS_NODE_PROFILE=$ROOT/probes/mle/teavm-engine/run-decps-node-profile.sh
TEAVM_DECPS_WARM_LIFECYCLE=$ROOT/probes/mle/teavm-engine/run-decps-warm-lifecycle.sh
TEAVM_DECPS_NODE_PROFILE_RANK=$ROOT/probes/mle/teavm-engine/rank-decps-node-profile.mjs
TEAVM_DECPS_NODE_PROFILE_VALIDATE=$ROOT/probes/mle/teavm-engine/validate-decps-node-profile.mjs
TEAVM_DECPS_ASYNC_JIT_COMPARE=$ROOT/probes/mle/teavm-engine/compare-decps-async-jit.mjs
TEAVM_DECPS_ASYNC_PLATEAU_COMPARE=$ROOT/probes/mle/teavm-engine/compare-decps-async-plateau.mjs
TEAVM_DECPS_RANK_COMPARE=$ROOT/probes/mle/teavm-engine/compare-decps-rank.mjs
TEAVM_DECPS_DUAL_CLOCK_COMPARE=$ROOT/probes/mle/teavm-engine/compare-decps-dual-clock-rank.mjs
TEAVM_LONG_FLAG_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-long-flag-cast.sql
TEAVM_LONG_FLAG_RUNNER=$ROOT/probes/mle/teavm-engine/run-long-flag-cast.sh
TEAVM_MOBJ_LOW_WORD_PATCH=$ROOT/probes/mle/teavm-engine/0008-teavm-authority-mobj-low-word.patch
TEAVM_MOBJ_LOW_WORD_PROPERTY=$ROOT/probes/mle/teavm-engine/src/build/java/doomdb/mle/engine/LongFlagLowWordPropertyTest.java
TEAVM_MOBJ_LOW_WORD_RUNNER=$ROOT/probes/mle/teavm-engine/run-mobj-low-word-candidate.sh
TEAVM_MOBJ_LOW_WORD_COMPARE=$ROOT/probes/mle/teavm-engine/compare-mobj-low-word-rank.mjs
TEAVM_DECPS_IDENTITY_CLASSIFICATION=$ROOT/artifacts/performance/pmle-decps-rank/identity-break-classification-2026-07-25.md
TEAVM_DECPS_SIMPLE_JIT=$ROOT/probes/mle/teavm-engine/run-decps-simple-jit.sh
TEAVM_PROFILE=$ROOT/probes/mle/teavm-engine/profile-ledger-node.mjs
TEAVM_PATCH=$ROOT/probes/mle/teavm-engine/0002-teavm-simulation-headless.patch
TEAVM_INIT_DIET_PATCH=$ROOT/probes/mle/teavm-engine/0004-teavm-authority-init-diet.patch
TEAVM_INIT_DIET_RUNNER=$ROOT/probes/mle/teavm-engine/run-init-diet-mle.sh
TEAVM_INIT_PROFILE=$ROOT/probes/mle/teavm-engine/profile-init-node.sh
TEAVM_MEMORY_CAL=$ROOT/probes/mle/teavm-engine/run-memory-calibration.sh
TEAVM_MEMORY_CAL_SQL=$ROOT/probes/mle/teavm-engine/calibrate-memory-mle.sql
TEAVM_DISPATCH_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-active-state-dispatch.sql
TEAVM_DISPATCH_RUNNER=$ROOT/probes/mle/teavm-engine/run-active-state-dispatch.sh
TEAVM_DISPATCH_AB=$ROOT/probes/mle/teavm-engine/run-dispatch-ab.sh
TEAVM_DIFFERENTIAL_RUNNER=$ROOT/probes/mle/teavm-engine/run-differential.sh
TEAVM_LEDGER_RUNNER=$ROOT/probes/mle/teavm-engine/run-ledger-differential.sh
TEAVM_WORKER_CUTOVER_RUNNER=$ROOT/probes/mle/teavm-engine/run-worker-cutover.sh
TEAVM_CADENCE_DECISION=$ROOT/artifacts/performance/pmle-worker-soak/checkpoint-cadence-decision-2026-07-29.md
TEAVM_BROWSER_REPLICA_PROFILE=$ROOT/probes/mle/teavm-engine/profile-browser-replica.mjs
TEAVM_WAN_RUNNER=$ROOT/probes/mle/teavm-engine/run-wan-matrix.sh
ALERT_SCANNER=$ROOT/scripts/oracle-alert-window.sh
TEAVM_LIVE_MATRIX=$ROOT/probes/mle/teavm-engine/run-live-command-matrix-mle.sh
HIDDEN_JIT_RUNNER=$ROOT/probes/mle/run-hidden-jit-matrix.sh
WASM2JS_README=$ROOT/probes/mle/teavm-engine/wasm2js/README.md
WASM2JS_PARITY=$ROOT/probes/mle/teavm-engine/wasm2js/run-node-parity.mjs
WASM2JS_I64_DIAGNOSTIC=$ROOT/probes/mle/teavm-engine/wasm2js/run-i64-lowering-diagnostics.sh
WASM2JS_SERIALIZER_WORKAROUND=$ROOT/probes/mle/teavm-engine/wasm2js/run-serializer-workaround.sh
WASM2JS_SERIALIZER_PATCH=$ROOT/probes/mle/teavm-engine/wasm2js/0004-canonical-save-low-word-workaround.patch
WASM2JS_PROBE=$ROOT/probes/mle/teavm-engine/wasm2js/src/main/java/doomdb/mle/wasm2js/Wasm2JsAuthorityProbe.java
WASM2JS_TOOLCHAIN_BUILD=$ROOT/probes/mle/teavm-engine/wasm2js/build-teavm-singlethread.sh
WASM2JS_TOOLCHAIN_PATCH=$ROOT/probes/mle/teavm-engine/wasm2js/0001-teavm-singlethread-no-cps.patch
WASM2JS_REPORT=$ROOT/artifacts/performance/pmle-wasm2js/REPORT.md
WASM2JS_MARKERS=$ROOT/artifacts/performance/pmle-wasm2js/evidence-markers.log
TEAVM_SIM_SOURCE=$ROOT/probes/mle/teavm-engine/src/main/java/doomdb/mle/engine/SimulationEngineReachabilityProbe.java
TEAVM_BSP_PROPERTY=$ROOT/probes/mle/teavm-engine/src/build/java/doomdb/mle/engine/IterativeBspTraversalPropertyTest.java
TEAVM_PRESENTATION_SOURCE=$ROOT/probes/mle/teavm-engine/src/main/java/doomdb/mle/engine/PresentationEngineReachabilityProbe.java
TEAVM_PRESENTATION_NODE=$ROOT/probes/mle/teavm-engine/run-presentation-node.mjs
TEAVM_PRESENTATION_FRAME_ORACLE=$ROOT/probes/mle/teavm-engine/rank-presentation-frame-node.mjs
TEAVM_PRESENTATION_FRAME_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-presentation-frame-mle.sql
TEAVM_PRESENTATION_FRAME_EXTRACTOR=$ROOT/probes/mle/teavm-engine/extract-presentation-frame-chain.mjs
TEAVM_BUILD_SHA_EXTRACTOR=$ROOT/probes/mle/teavm-engine/extract-build-sha.mjs
TEAVM_STREAM_HASHER=$ROOT/probes/mle/teavm-engine/hash-expanded-command-stream.mjs
TEAVM_PRESENTATION_FRAME_COMPARATOR=$ROOT/probes/mle/teavm-engine/compare-presentation-frame-rank.mjs
TEAVM_PRESENTATION_TRANSPORT_COMPARATOR=$ROOT/probes/mle/teavm-engine/compare-presentation-transport-rank.mjs
TEAVM_PRESENTATION_BIND_CAPABILITY=$ROOT/probes/mle/teavm-engine/extract-presentation-bind-capability.mjs
TEAVM_PRESENTATION_BIND_SOURCE=$ROOT/probes/mle/teavm-engine/presentation-bind-wrapper.mjs
TEAVM_PRESENTATION_BIND_INSTALL=$ROOT/probes/mle/teavm-engine/install-presentation-bind-wrapper.sh
TEAVM_PRESENTATION_BIND_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-presentation-bind-mle.sql
TEAVM_PRESENTATION_BIND_CLEANUP=$ROOT/probes/mle/teavm-engine/cleanup-presentation-bind-wrapper.sql
TEAVM_PRESENTATION_DECPS_RUNNER=$ROOT/probes/mle/teavm-engine/run-presentation-decps-rank.sh
TEAVM_OCI_PRESENTATION_DECPS_RUNNER=$ROOT/probes/mle/teavm-engine/run-oci-presentation-decps-rank.sh
TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR=$ROOT/probes/mle/teavm-engine/evaluate-oci-presentation-decps.mjs
REPORT=$ROOT/reports/performance-PMLE-mle-26ai-2026-07-22.md
TEAVM_REPORT=$ROOT/probes/mle/teavm-engine/REPORT.md
VERSIONS=$ROOT/versions.lock
AUTHORITY_TS=$ROOT/client/src/authority.ts
AUTHORITY_MIRROR_TS=$ROOT/client/src/authority-mirror.ts
AUTHORITY_BATCH_TS=$ROOT/client/src/authority-batch.ts
AUTHORITY_WAN_TS=$ROOT/client/src/authority-wan.ts
AUTHORITY_SQL=$ROOT/sql/sim/086_mle_authority_delta.sql
AUTHORITY_TRANSPORT=$ROOT/sql/sim/087_mle_transition_transport.sql
AUTHORITY_TRANSPORT_SCHEMA=$ROOT/sql/schema/052_mle_authority_transport.sql
AUTHORITY_TRANSPORT_TEST=$ROOT/tests/verify-mle-transition-transport.sql
MLE_MATCH_RUNTIME=$ROOT/sql/sim/088_mle_match_runtime.sql
MLE_LIVE_FRAME_LOADER=$ROOT/probes/mle/load-live-frame-module.sh
MLE_LIVE_FRAME_SCHEMA=$ROOT/sql/schema/064_mle_live_frame.sql
MLE_FRAME_STAGE_SCHEMA=$ROOT/sql/schema/067_mle_frame_stage_telemetry.sql
MLE_LIVE_FRAME_TRANSPORT=$ROOT/sql/sim/089_mle_live_frame_transport.sql
MLE_LIVE_FRAME_COORDINATOR=$ROOT/probes/mle/dvl2-world-raster-coordinator.mjs
MLE_RENDERER_ASSET_PACK_BUILDER=$ROOT/probes/mle/build-renderer-asset-packs.mjs
MLE_LIVE_WORLD_BUILDER=$ROOT/probes/mle/free-live-teavm/build-world-raster-source.mjs
MLE_LIVE_UNIFIED_MODULE=$ROOT/probes/mle/free-live-teavm/src/main/java/doomdb/mle/renderer/FreeLiveUnifiedRendererModule.java
MLE_LIVE_FRAME_E2E=$ROOT/tests/verify-mle-live-frame-e2e.mjs
ADB_ADMIN_SQL=$ROOT/scripts/adb-admin-sql.sh
MLE_LIVE_FRAME_E2E_RUNNER=$ROOT/tests/run-mle-live-frame-e2e.sh
MLE_LIVE_FRAME_CROSS_SLOT=$ROOT/tests/run-mle-live-frame-cross-slot.sh
MLE_LIVE_FRAME_RECOVERY=$ROOT/tests/run-mle-live-frame-recovery.sh
MLE_LIVE_FRAME_TRANSPORT_SOAK=$ROOT/tests/run-mle-live-frame-transport-soak.sh
MLE_LIVE_FRAME_RING_WRAP=$ROOT/tests/run-mle-live-frame-ring-wrap.sh
MLE_LIVE_FRAME_DIFFERENTIALS=$ROOT/probes/mle/teavm-engine/run-live-frame-authority-differentials.sh
MLE_LIVE_FRAME_TWO_POV=$ROOT/tests/run-oci-live-frame-two-pov.sh
MLE_LIVE_FRAME_TWO_POV_EVALUATOR=$ROOT/tests/evaluate-live-frame-two-pov.mjs
MLE_LIVE_FRAME_ARTIFACT_MARKER=$ROOT/scripts/verify-live-frame-artifact-marker.mjs
MULTIPLAYER_CLIENT=$ROOT/tests/verify-p13.3-multiplayer-client.mjs
MULTIPLAYER_PERFORMANCE=$ROOT/tests/verify-p13.5-multiplayer-performance.sh
MLE_PIXEL_BATCH_SOURCE=$ROOT/client/src/pixel-batch.ts
MLE_PIXEL_BATCH_STAGING=$ROOT/client/staging/pixel-batch.js
MLE_PIXEL_BATCH_DIST=$ROOT/client/dist/play/pixel-batch.js
MLE_COLUMN_MAJOR_TEST=$ROOT/tests/verify-column-major-blitter.mjs
MLE_TEMPORAL_SOLO_TEST=$ROOT/tests/verify-temporal-solo-coordinator-node.mjs
MLE_TEMPORAL_VIEW_BUNDLE_PATCHER=$ROOT/probes/mle/teavm-engine/patch-coordinator-temporal-view-bundle.mjs
MLE_TEMPORAL_VIEW_BUNDLE_TEST=$ROOT/tests/verify-mle-live-frame-dpv2.sql
MLE_NATIVE_TEMPORAL_PATCHER=$ROOT/probes/mle/teavm-engine/patch-coordinator-native-temporal-synthesis.mjs
MLE_STAGGERED_MULTIVIEW_PATCHER=$ROOT/probes/mle/teavm-engine/patch-coordinator-staggered-multiview.mjs
MLE_NATIVE_TEMPORAL_BENCH=$ROOT/probes/mle/teavm-engine/benchmark-oci-temporal-native-synthesis.sql
MLE_PUBLIC_MOVEMENT_GATE=$ROOT/probes/mle/teavm-engine/measure-public-exact-fps.mjs
MLE_WORKER_LIFECYCLE=$ROOT/sql/sim/083_worker_lifecycle.sql
MLE_WORKER_LIFECYCLE_SCHEMA=$ROOT/sql/schema/062_mle_warm_lifecycle.sql
MLE_WARM_LIFECYCLE_TEST=$ROOT/tests/verify-mle-warm-lifecycle.sql
MLE_RECOVERY_TELEMETRY_SCHEMA=$ROOT/sql/schema/064_mle_recovery_telemetry.sql
MLE_ASYNC_CHECKPOINT_SCHEMA=$ROOT/sql/schema/066_async_standby_checkpoint.sql
MLE_MATCH_WORKER=$ROOT/sql/sim/084_multiplayer_worker.sql
MLE_MATCH_WORKER_TEST=$ROOT/tests/verify-mle-match-worker-cutover.sql
MLE_SESSION_CLEANUP=$ROOT/sql/sim/085_session_cleanup.sql
MULTIPLAYER_SCHEMA=$ROOT/sql/schema/047_multiplayer.sql
DOOM_API=$ROOT/sql/rest/010_doom_api.sql
MULTIPLAYER_CLIENT_TS=$ROOT/client/src/multiplayer.ts
MULTIPLAYER_SOAK=$ROOT/tests/verify-p13.5-multiplayer-soak.mjs
IWAD_LOADER=$ROOT/tools/mochadoom/DoomMochaIwadLoader.java
RUNTIME_GRANTS=$ROOT/deploy/local/initdb/10-doom-runtime-grants.sql
ENVIRONMENT_SQL=$ROOT/probes/mle/teavm-engine/environment-metadata.sql
ARTIFACT_SQL=$ROOT/probes/mle/teavm-engine/artifact-metadata.sql
AUTHORITY_TEST=$ROOT/tests/verify-authority-delta.mjs
AUTHORITY_MIRROR_TEST=$ROOT/tests/verify-authority-mirror.mjs
AUTHORITY_BATCH_TEST=$ROOT/tests/verify-authority-batch.mjs
AUTHORITY_WAN_TEST=$ROOT/tests/verify-authority-wan.mjs
WAN_PROXY=$ROOT/tests/wan-latency-proxy.mjs
WAN_PROFILES=$ROOT/tests/fixtures/wan-profiles.json
WAN_SOAK=$ROOT/tests/verify-p13.5-multiplayer-soak.mjs
RETAINED_WORKER_TEST=$ROOT/tests/verify-p13.2-retained-match-worker.sql

fail() {
  printf '%s\n' "PMLE source verification: $*" >&2
  exit 1
}

line_of() {
  grep -n -m 1 "$1" "$2" | cut -d: -f1
}

for file in "$INSTALL" "$BENCHMARK" "$RUNNER" "$CLEANUP" \
  "$NATIVE_INSTALL" "$NATIVE_BENCHMARK" "$NATIVE_CLEANUP" \
  "$HYBRID_INSTALL" "$HYBRID_BENCHMARK" "$HYBRID_CLEANUP" \
  "$COMMAND_BENCHMARK" "$BIND_INSTALL" "$BIND_BENCHMARK" "$BIND_CLEANUP" \
  "$ADB_INSTALL" "$ADB_BENCHMARK" "$ADB_CLEANUP" "$ADB_RUNNER" \
  "$TEAVM_TIC0_BUILDER" "$TEAVM_TIC0_LOADER" \
  "$TEAVM_SIM_LOADER" "$TEAVM_SLICE_LOADER" "$TEAVM_SIM_CLEANUP" "$TEAVM_LEDGER" \
  "$TEAVM_CANONICAL_BENCH" "$TEAVM_RECOVERY" "$TEAVM_MULTIPLAYER" \
  "$TEAVM_MULTI_BENCH" "$TEAVM_MULTI_RECOVERY" "$TEAVM_MULTI_SOAK" \
  "$TEAVM_MULTI_SOAK_RUNNER" "$TEAVM_COOP" "$TEAVM_MEMBERSHIP_DIFF" "$TEAVM_BUILD" \
  "$TEAVM_DECPS_LEDGER_POSTFLIGHT" "$TEAVM_DECPS_READINESS" \
  "$TEAVM_DECPS_REPRODUCIBILITY" \
  "$TEAVM_DECPS_NODE_PROFILE" "$TEAVM_DECPS_WARM_LIFECYCLE" \
  "$TEAVM_DECPS_NODE_PROFILE_RANK" "$TEAVM_DECPS_NODE_PROFILE_VALIDATE" \
  "$TEAVM_DECPS_ASYNC_JIT_COMPARE" "$TEAVM_DECPS_ASYNC_PLATEAU_COMPARE" \
  "$TEAVM_DECPS_RANK_COMPARE" \
  "$TEAVM_DECPS_DUAL_CLOCK_COMPARE" \
  "$TEAVM_LONG_FLAG_BENCH" "$TEAVM_LONG_FLAG_RUNNER" \
  "$TEAVM_MOBJ_LOW_WORD_PATCH" "$TEAVM_MOBJ_LOW_WORD_PROPERTY" \
  "$TEAVM_MOBJ_LOW_WORD_RUNNER" "$TEAVM_MOBJ_LOW_WORD_COMPARE" \
  "$TEAVM_DECPS_SIMPLE_JIT" "$TEAVM_DEPLOYMENT_STATE" \
  "$TEAVM_LIFECYCLE_MANIFEST" \
  "$TEAVM_PROFILE" "$TEAVM_PATCH" "$TEAVM_INIT_DIET_PATCH" \
  "$TEAVM_INIT_DIET_RUNNER" "$TEAVM_INIT_PROFILE" "$TEAVM_MEMORY_CAL" \
  "$TEAVM_MEMORY_CAL_SQL" "$TEAVM_DISPATCH_BENCH" \
  "$TEAVM_DISPATCH_RUNNER" "$TEAVM_DISPATCH_AB" "$TEAVM_DIFFERENTIAL_RUNNER" \
  "$TEAVM_WORKER_CUTOVER_RUNNER" "$TEAVM_BROWSER_REPLICA_PROFILE" \
  "$TEAVM_WAN_RUNNER" \
  "$MLE_TEMPORAL_SOLO_TEST" "$MLE_PUBLIC_MOVEMENT_GATE" \
  "$WASM2JS_README" "$WASM2JS_PARITY" "$WASM2JS_PROBE" "$WASM2JS_TOOLCHAIN_BUILD" \
  "$WASM2JS_TOOLCHAIN_PATCH" "$WASM2JS_I64_DIAGNOSTIC" \
  "$WASM2JS_SERIALIZER_WORKAROUND" "$WASM2JS_SERIALIZER_PATCH" \
  "$WASM2JS_REPORT" "$WASM2JS_MARKERS" \
  "$TEAVM_PRESENTATION_BUILD" "$TEAVM_PRESENTATION_SOURCE" \
  "$TEAVM_PRESENTATION_NODE" "$TEAVM_PRESENTATION_FRAME_ORACLE" \
  "$TEAVM_PRESENTATION_FRAME_BENCH" "$TEAVM_PRESENTATION_FRAME_EXTRACTOR" \
  "$TEAVM_BUILD_SHA_EXTRACTOR" "$TEAVM_STREAM_HASHER" \
  "$TEAVM_PRESENTATION_FRAME_COMPARATOR" \
  "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" \
  "$TEAVM_PRESENTATION_BIND_CAPABILITY" \
  "$TEAVM_PRESENTATION_BIND_SOURCE" "$TEAVM_PRESENTATION_BIND_INSTALL" \
  "$TEAVM_PRESENTATION_BIND_BENCH" \
  "$TEAVM_PRESENTATION_BIND_CLEANUP" "$TEAVM_PRESENTATION_DECPS_RUNNER" \
  "$TEAVM_SIM_SOURCE" "$TEAVM_BSP_PROPERTY" \
  "$MLE_RENDERER_ASSET_PACK_BUILDER" \
  "$REPORT" "$TEAVM_REPORT" "$VERSIONS" \
  "$AUTHORITY_TS" "$AUTHORITY_MIRROR_TS" "$AUTHORITY_BATCH_TS" \
  "$AUTHORITY_WAN_TS" \
  "$AUTHORITY_SQL" "$AUTHORITY_TRANSPORT" "$AUTHORITY_TRANSPORT_SCHEMA" \
  "$MLE_MATCH_RUNTIME" "$MLE_WORKER_LIFECYCLE" \
  "$MLE_WORKER_LIFECYCLE_SCHEMA" "$MLE_ASYNC_CHECKPOINT_SCHEMA" \
  "$MLE_MATCH_WORKER" "$MLE_MATCH_WORKER_TEST" \
  "$DOOM_API" "$IWAD_LOADER" "$RUNTIME_GRANTS" \
  "$ENVIRONMENT_SQL" "$ARTIFACT_SQL" \
  "$AUTHORITY_TRANSPORT_TEST" "$AUTHORITY_TEST" "$AUTHORITY_MIRROR_TEST" \
  "$AUTHORITY_BATCH_TEST" "$AUTHORITY_WAN_TEST" "$WAN_PROXY" "$WAN_PROFILES" \
  "$WAN_SOAK"; do
  [ -f "$file" ] || fail "missing ${file#$ROOT/}"
done
[ -x "$RUNNER" ] || fail 'probe runner is not executable'
[ -x "$ADB_RUNNER" ] || fail 'ADB probe runner is not executable'
[ -x "$TEAVM_SIM_LOADER" ] || fail 'TeaVM simulation loader is not executable'
[ -x "$TEAVM_INIT_DIET_RUNNER" ] || fail 'TeaVM init-diet runner is not executable'
[ -x "$TEAVM_INIT_PROFILE" ] || fail 'TeaVM init profile wrapper is not executable'
[ -x "$TEAVM_TIC0_LOADER" ] || fail 'TeaVM tic-zero bank loader is not executable'
[ -x "$TEAVM_MULTI_SOAK_RUNNER" ] || fail 'TeaVM multiplayer soak runner is not executable'
[ -x "$TEAVM_MEMORY_CAL" ] || fail 'TeaVM memory calibration runner is not executable'
[ -x "$TEAVM_DISPATCH_RUNNER" ] || fail 'TeaVM ActiveStates dispatch runner is not executable'
[ -x "$TEAVM_DISPATCH_AB" ] || fail 'TeaVM dispatch A/B runner is not executable'
[ -x "$TEAVM_DIFFERENTIAL_RUNNER" ] || fail 'TeaVM differential runner is not executable'
[ -x "$TEAVM_LEDGER_RUNNER" ] || fail 'TeaVM ledger differential runner is not executable'
[ -x "$MLE_LIVE_FRAME_DIFFERENTIALS" ] ||
  fail 'live-frame authority differential runner is not executable'
[ -x "$TEAVM_DECPS_READINESS" ] || fail 'de-CPS promotion readiness checker is not executable'
[ -x "$TEAVM_DECPS_LEDGER_POSTFLIGHT" ] ||
  fail 'de-CPS ledger postflight is not executable'
[ -x "$TEAVM_DECPS_REPRODUCIBILITY" ] ||
  fail 'de-CPS reproducibility runner is not executable'
[ -x "$TEAVM_DECPS_PROMOTION" ] ||
  fail 'de-CPS promotion transaction is not executable'
[ -x "$TEAVM_DECPS_DEPLOY" ] ||
  fail 'de-CPS deployment transaction is not executable'
node "$TEAVM_DECPS_PROMOTION" --self-test >/dev/null ||
  fail 'de-CPS promotion transaction self-test failed'
[ -x "$TEAVM_DECPS_NODE_PROFILE" ] ||
  fail 'de-CPS Node profile runner is not executable'
[ -x "$TEAVM_DECPS_SIMPLE_JIT" ] ||
  fail 'de-CPS SIMPLE JIT runner is not executable'
[ -x "$TEAVM_LONG_FLAG_RUNNER" ] ||
  fail 'long-flag cast runner is not executable'
[ -x "$TEAVM_MOBJ_LOW_WORD_RUNNER" ] ||
  fail 'mobj low-word candidate runner is not executable'
node "$TEAVM_MOBJ_LOW_WORD_COMPARE" --self-test >/dev/null ||
  fail 'mobj low-word rank comparator self-test failed'
node "$TEAVM_DECPS_ASYNC_PLATEAU_COMPARE" --self-test >/dev/null ||
  fail 'de-CPS async plateau comparator self-test failed'
[ -x "$TEAVM_DEPLOYMENT_STATE" ] ||
  fail 'de-CPS deployment state transition tool is not executable'
[ -x "$TEAVM_LIFECYCLE_MANIFEST" ] ||
  fail 'de-CPS lifecycle manifest builder is not executable'
node "$TEAVM_LIFECYCLE_MANIFEST" --self-test >/dev/null ||
  fail 'de-CPS lifecycle manifest artifact-binding self-test failed'
node "$TEAVM_DEPLOYMENT_STATE" --self-test >/dev/null ||
  fail 'de-CPS deployment state artifact-binding self-test failed'
[ -x "$WASM2JS_I64_DIAGNOSTIC" ] ||
  fail 'wasm2js i64 diagnostic runner is not executable'
[ -x "$WASM2JS_SERIALIZER_WORKAROUND" ] ||
  fail 'wasm2js serializer workaround runner is not executable'
[ -x "$TEAVM_WORKER_CUTOVER_RUNNER" ] || fail 'TeaVM worker cutover runner is not executable'
[ -x "$TEAVM_WAN_RUNNER" ] || fail 'TeaVM WAN matrix runner is not executable'
[ -x "$TEAVM_PRESENTATION_BIND_INSTALL" ] ||
  fail 'presentation session-bind loader is not executable'
[ -x "$TEAVM_COOP" ] || fail 'TeaVM co-op differential generator is not executable'
for evidence_runner in "$TEAVM_WORKER_CUTOVER_RUNNER" \
    "$TEAVM_DECPS_DEPLOY" \
    "$TEAVM_MULTI_SOAK_RUNNER" \
    "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" \
    "$TEAVM_DIFFERENTIAL_RUNNER" \
    "$TEAVM_DECPS_NODE_PROFILE" "$TEAVM_PRESENTATION_DECPS_RUNNER" \
    "$TEAVM_DECPS_SIMPLE_JIT" "$WASM2JS_I64_DIAGNOSTIC" \
    "$WASM2JS_SERIALIZER_WORKAROUND"; do
  grep -Fq '[r]un-decps-ledger' "$evidence_runner" ||
    fail "evidence runner can contend with the exhaustive ledger: $evidence_runner"
done

grep -qi '^create mle env doom_mle_bench_env pure' "$INSTALL" || fail 'PURE environment missing'
grep -q 'signature.*Out<Uint8Array>' "$INSTALL" || fail 'RAW OUT call specification missing'
grep -q '"webAssembly":"undefined"' "$RUNNER" || fail 'WebAssembly capability fence missing'
grep -q 'c_renderer_p95_limit_ms constant number := 20' "$BENCHMARK" || fail '20 ms renderer gate missing'
grep -q 'c_renderer_p99_limit_ms constant number := 33.3' "$BENCHMARK" || fail '33.3 ms p99 gate missing'
grep -q 'c_full_samples.*:= 300' "$BENCHMARK" || fail '300-frame sample gate missing'
grep -q "utl_raw.length(l_chunk0) <> c_chunk_bytes" "$BENCHMARK" || fail 'first RAW length fence missing'
grep -q "utl_raw.length(l_chunk1) <> c_chunk_bytes" "$BENCHMARK" || fail 'second RAW length fence missing'
grep -q 'doom_mle_bench_counter' "$BENCHMARK" || fail 'retained module-state check missing'
grep -q 'PMLE_COLUMN_MATRIX' "$BENCHMARK" || fail 'cached/dynamic column matrix missing'
grep -q 'dbms_utility.get_cpu_time' "$BENCHMARK" || fail 'server CPU timing missing'
grep -q 'native-cleanup.sql' "$RUNNER" || fail 'native cleanup path missing'
grep -q 'hybrid-cleanup.sql' "$RUNNER" || fail 'hybrid cleanup path missing'
grep -q 'cleanup.sql' "$RUNNER" || fail 'MLE cleanup path missing'
grep -q 'plsql_code_type=native' "$NATIVE_INSTALL" || fail 'native PL/SQL compile missing'
grep -q 'utl_raw.translate' "$NATIVE_INSTALL" || fail 'native RAW translation missing'
grep -q 'render_hex_block_columns' "$NATIVE_INSTALL" || fail 'native blocked gather probe missing'
grep -q 'render_buffered_frame' "$NATIVE_INSTALL" || fail 'native framebuffer probe missing'
grep -q 'doom_mle_bench_commands' "$COMMAND_BENCHMARK" || fail 'MLE command boundary missing'
grep -q 'PMLE_COMMAND_GATE|PASS' "$COMMAND_BENCHMARK" || fail 'command compositor gate missing'
grep -q 'systimestamp' "$BIND_BENCHMARK" || fail 'wall-clock bind timing missing'
grep -q 'c_batch constant pls_integer:=20' "$BIND_BENCHMARK" || fail 'batched wall-clock bind timing missing'
grep -q 'non_pure_session_execute_blob' "$BIND_BENCHMARK" || fail 'non-PURE bind comparison missing'
grep -q 'create mle env doom_mle_adb_env pure' "$ADB_INSTALL" || fail 'ADB PURE environment missing'
grep -q 'systimestamp' "$ADB_BENCHMARK" || fail 'ADB wall-clock timing missing'
grep -q 'c_batch constant pls_integer:=20' "$ADB_BENCHMARK" || fail 'ADB timing batch missing'
grep -q 'PMLE_ADB_DECISION|REOPEN_EXACT_RENDERER' "$ADB_BENCHMARK" || fail 'ADB reopen threshold missing'
grep -q 'PMLE_ADB_DECISION|CLOSE_EXACT_RENDERER' "$ADB_BENCHMARK" || fail 'ADB close threshold missing'
grep -q 'REJECTED_BEFORE_MLE' "$WASM2JS_README" ||
  fail 'wasm2js terminal rejection missing'
grep -q 'compareCanonical(0)' "$WASM2JS_PARITY" ||
  fail 'wasm2js tic-zero canonical gate missing'
grep -q 'PMLE_WASM2JS_I64_REDUCTION|PASS' "$WASM2JS_PARITY" ||
  fail 'wasm2js i64 reduction gate missing'
grep -q '"$lowerer" "$wasm" "$lowered"' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q '"$wasm2js" -O0 "$lowered"' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q '"$wasm_dis" --all-features --emit-module-names' \
    "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'PMLE_WASM2JS_SERIALIZER_DISASSEMBLY|BEGIN' \
    "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'DOOMDB_WASM2JS_TICS=0' "$WASM2JS_I64_DIAGNOSTIC" ||
  fail 'wasm2js i64 O0/disassembly diagnostics are not fail-closed'
grep -q 'CALL_BOUNDARY_HIGH_WORD_LOSS' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'PMLE_WASM2JS_I64_REDUCTION_CASE' "$WASM2JS_PARITY" &&
  grep -q 'packedOptions' "$WASM2JS_SERIALIZER_PATCH" &&
  grep -q 'DOOMDB_WASM2JS_SOURCE_PATCH' \
    "$WASM2JS_SERIALIZER_WORKAROUND" &&
  grep -q 'adapter_patch_sha256=none' \
    "$WASM2JS_SERIALIZER_WORKAROUND" &&
  grep -q 'DOOMDB_WASM2JS_TICS=100' \
    "$WASM2JS_SERIALIZER_WORKAROUND" &&
  grep -q 'CANDIDATE_FOR_DIRECT_MLE_RANK' \
    "$WASM2JS_SERIALIZER_WORKAROUND" ||
  fail 'wasm2js call-boundary diagnosis cannot trigger the gated serializer workaround'
for export_name in doom_i64_constant_high doom_i64_field_high \
    doom_i64_field_copy_high doom_i64_array_high doom_i64_call_high \
    doom_i64_flag_or_high; do
  grep -q "$export_name" "$WASM2JS_PROBE" ||
    fail "wasm2js i64 reduction export missing: $export_name"
done
grep -q "commit='b3a245b7d9034ff35cdfab2def057a3d4f256efb'" \
  "$WASM2JS_TOOLCHAIN_BUILD" ||
  fail 'wasm2js TeaVM fork commit is not pinned'
grep -q 'git -C "$source_dir" apply --check' "$WASM2JS_TOOLCHAIN_BUILD" ||
  fail 'wasm2js TeaVM fork patch is not fail-closed'
grep -q 'CoroutineTransformation' "$WASM2JS_TOOLCHAIN_PATCH" ||
  fail 'wasm2js TeaVM single-thread patch missing'
grep -q 'binaryen_i64_high_word_loss' "$WASM2JS_REPORT" ||
  fail 'wasm2js structural rejection reason missing'
grep -q '0bfda9dea546dbba608f9abf55ed2c265adef6dec43729524d3872e67e1c2bd9' \
  "$WASM2JS_REPORT" ||
  fail 'wasm2js Binaryen 131/current lowering-source comparison missing'
grep -q 'oracle_mle_load=NOT_RUN' "$WASM2JS_MARKERS" ||
  fail 'wasm2js no-MLE-load evidence missing'
grep -q 'DOOMDB_CLOUD_EXECUTE.*YES' "$ADB_RUNNER" || fail 'ADB execution opt-in missing'
grep -q 'ADB_PASSWORD' "$ADB_RUNNER" || fail 'ADB credential fence missing'
grep -q 'adb-cleanup.sql' "$ADB_RUNNER" || fail 'ADB cleanup path missing'
grep -q 'doom-mle-simulation-engine-headless.js' "$TEAVM_SIM_LOADER" || fail 'full-ticker TeaVM artifact missing'
grep -q 'using blob' "$TEAVM_SIM_LOADER" || fail 'full-ticker BLOB module load missing'
grep -q 'PMLE_TEAVM_SIMULATION_LOAD' "$TEAVM_SIM_LOADER" || fail 'full-ticker load marker missing'
grep -q -- '--javascript=' "$TEAVM_SIM_LOADER" ||
  fail 'MLE diagnostic loader cannot select an exact A/B artifact'
grep -q 'production load cannot override content-addressed artifacts' \
  "$TEAVM_SIM_LOADER" ||
  fail 'MLE production loader permits diagnostic artifact overrides'
grep -q 'base64_fold_width=2000' "$TEAVM_SIM_LOADER" || fail 'full-ticker safe base64 fold missing'
grep -Fq 'while IFS= read -r piece || [[ -n "$piece" ]]' "$TEAVM_SIM_LOADER" || fail 'full-ticker final base64 piece fence missing'
grep -q 'PMLE_TEAVM_STAGING_GATE|PASS' "$TEAVM_SIM_LOADER" || fail 'full-ticker database staging SHA gate missing'
grep -q 'whenever sqlerror exit sql.sqlcode rollback' "$TEAVM_SIM_LOADER" || fail 'full-ticker fail-closed SQL fence missing'
grep -q 'dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)' "$TEAVM_SIM_LOADER" || fail 'full-ticker database source hash missing'
grep -q 'dbms_crypto.hash(l_tables,dbms_crypto.hash_sh256)' "$TEAVM_SIM_LOADER" || fail 'canonical table database hash missing'
test "$(line_of 'PMLE_TEAVM_STAGING_GATE|PASS' "$TEAVM_SIM_LOADER")" -lt \
  "$(line_of 'create mle module doom_teavm_simulation' "$TEAVM_SIM_LOADER")" || fail 'full-ticker staging gate runs after module creation'
grep -q 'base64_fold_width=2000' "$TEAVM_TIC0_LOADER" || fail 'tic-zero bank safe base64 fold missing'
grep -Fq 'while IFS= read -r piece || [[ -n "$piece" ]]' "$TEAVM_TIC0_LOADER" || fail 'tic-zero bank final base64 piece fence missing'
grep -q 'dbms_crypto.hash(checkpoint_blob,dbms_crypto.hash_sh256)' "$TEAVM_TIC0_LOADER" || fail 'tic-zero bank database SHA gate missing'
grep -q 'PMLE_TIC0_BANK_STAGING|PASS' "$TEAVM_TIC0_LOADER" || fail 'tic-zero bank staging marker missing'
grep -q 'pathToFileURL(path.resolve(authorityPath))' "$TEAVM_TIC0_BUILDER" ||
  fail 'tic-zero bank builder does not bind its authority input'
grep -q 'base64_fold_width=2000' "$TEAVM_SLICE_LOADER" || fail 'TeaVM slice safe base64 fold missing'
grep -Fq 'while IFS= read -r piece || [[ -n "$piece" ]]' "$TEAVM_SLICE_LOADER" || fail 'TeaVM slice final base64 piece fence missing'
grep -q 'PMLE_TEAVM_PROBE_STAGING_GATE|PASS' "$TEAVM_SLICE_LOADER" || fail 'TeaVM slice database staging SHA gate missing'
grep -q 'whenever sqlerror exit sql.sqlcode rollback' "$TEAVM_SLICE_LOADER" || fail 'TeaVM slice fail-closed SQL fence missing'
test "$(line_of 'PMLE_TEAVM_PROBE_STAGING_GATE|PASS' "$TEAVM_SLICE_LOADER")" -lt \
  "$(line_of 'create mle module doom_teavm_probe' "$TEAVM_SLICE_LOADER")" || fail 'TeaVM slice staging gate runs after module creation'
grep -q 'drop mle module doom_teavm_simulation' "$TEAVM_SIM_CLEANUP" || fail 'full-ticker cleanup missing'
grep -q 'doom_teavm_sim_step_command' "$TEAVM_LEDGER" || fail 'exact ledger command path missing'
grep -q 'doom_teavm_sim_canonical_chunk' "$TEAVM_LEDGER" || fail 'canonical ledger export missing'
grep -q 'PMLE_LEDGER_PROGRESS' "$TEAVM_LEDGER" || fail 'ledger cumulative progress marker missing'
grep -q 'l_progress_digest' "$TEAVM_LEDGER" || fail 'ledger cumulative digest state missing'
node "$TEAVM_LEDGER_PROGRESS_AUDIT" --self-test >/dev/null ||
  fail 'ledger progress comparator self-test failed'
bash -n "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority reproducibility runner has invalid shell syntax'
grep -Fq '[[ "${PMLE_LIVE_FRAME_REPRODUCIBILITY:-NO}" == YES ]]' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild lacks an explicit activation fence'
grep -Fq 'candidate_patch_set" == none' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild does not bind the candidate patch-set truth'
grep -Fq 'DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch"' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild does not apply the production patch'
grep -Fq 'classification=TERMINAL|markers=133|through_tic=13272' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq \
    'ledger_terminal_sha=089ba1518faf0e62be1c59d09e576c00e75c1845c00c3d45e497f7e3b7048584' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq 'PMLE_CANDIDATE_PAIR|classification=UNPROMOTED_CANDIDATE' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq 'PMLE_ARTIFACT|source_bytes=' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq 'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq 'ledger_terminal_sha256=%s' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild is not bound to terminal ledger evidence'
grep -Fq 'file_identity "$rebuilt" "$expected_bytes" "$expected_sha"' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" &&
  grep -Fq 'cmp -s "$candidate" "$rebuilt"' \
    "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild does not require byte-exact c613 reproduction'
grep -Fq 'PMLE_LIVE_FRAME_REPRODUCIBILITY|PASS|' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY" ||
  fail 'live-frame authority rebuild lacks a terminal evidence marker'
test "$(line_of 'PMLE_LIVE_FRAME_REPRODUCIBILITY=YES after' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY")" -lt \
  "$(line_of '"$project/build-simulation.sh"' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY")" ||
  fail 'live-frame authority rebuild activation fence follows execution'
test "$(line_of 'expected_ledger_audit=' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY")" -lt \
  "$(line_of '"$project/build-simulation.sh"' \
  "$TEAVM_LIVE_FRAME_REPRODUCIBILITY")" ||
  fail 'live-frame authority terminal-ledger fence follows execution'
if grep -Eq 'doom_teavm_sim_(checkpoint|restore)|doom_mocha_[a-z_]*(checkpoint|restore)' "$TEAVM_LEDGER"; then
  fail 'promotion ledger must not checkpoint or restore'
fi
grep -q 'dbms_crypto.hash' "$TEAVM_LEDGER" || fail 'native canonical hash missing'
grep -q "emit_summary('ticker'" "$TEAVM_LEDGER_COMPONENTS" ||
  fail 'ledger component ticker attribution missing'
grep -q "emit_summary('canonical_material'" "$TEAVM_LEDGER_COMPONENTS" ||
  fail 'ledger component canonical attribution missing'
grep -q "emit_summary('raw_export'" "$TEAVM_LEDGER_COMPONENTS" ||
  fail 'ledger component export attribution missing'
grep -q 'PMLE_LEDGER_COMPONENT_PROFILE|PASS' "$TEAVM_LEDGER_COMPONENTS" ||
  fail 'ledger component terminal marker missing'
grep -q 'PMLE_COMPONENT_AB_EXECUTE' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B execution opt-in missing'
"$TEAVM_LEDGER_COMPONENT_EXTRACTOR" --self-test |
  grep -q '^PMLE_LEDGER_COMPONENT_EXTRACTOR|PASS|' ||
  fail 'ledger component digest extractor offline self-test failed'
grep -q '"$digest_extractor" --self-test' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not dry-run its extractor before execution'
test "$(line_of '"$digest_extractor" --self-test' "$TEAVM_LEDGER_COMPONENT_RUNNER")" -lt \
  "$(line_of 'PMLE_COMPONENT_AB_EXECUTE' "$TEAVM_LEDGER_COMPONENT_RUNNER")" ||
  fail 'ledger component extractor dry-run occurs after execution opt-in'
grep -Fq "pgrep -f '[b]uild-ledger-differential.mjs'" \
  "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B is not fenced from the promotion ledger'
grep -q 'doomdb-pmle-ledger-' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not honor the run-lifetime ledger lock'
grep -q 'PMLE_HOST_QUIESCENCE|PASS' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B host-quiescence evidence missing'
grep -q 'PMLE_BENCHMARK_POOL|PARKED|live_slots=' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not park retained sessions before measurement'
grep -q 'start_warm_pool' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not restore the retained pool'
grep -q 'restore_production_module' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not fail-closed restore production'
grep -q 'artifact-metadata.sql' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B exact deployed artifact evidence missing'
grep -q 'component A/B canonical digest mismatch' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not bind both artifacts to one state digest'
grep -q -- '--production' "$TEAVM_LEDGER_COMPONENT_RUNNER" ||
  fail 'ledger component A/B does not restore production module'
grep -q 'stage=mle-material' "$TEAVM_CANONICAL_BENCH" || fail 'canonical stage benchmark missing'
grep -q 'PMLE_TEAVM_RECOVERY|PASS' "$TEAVM_RECOVERY" || fail 'MLE recovery gate missing'
grep -q 'PMLE_TEAVM_MULTIPLAYER|PASS' "$TEAVM_MULTIPLAYER" || fail 'MLE multiplayer differential missing'
grep -q 'PMLE_TEAVM_MULTI_TICKER' "$TEAVM_MULTI_BENCH" || fail 'MLE multiplayer benchmark missing'
grep -q 'fresh_context=1' "$TEAVM_MULTI_RECOVERY" || fail 'fresh-context multiplayer recovery gate missing'
grep -q 'PMLE_TEAVM_MULTI_SOAK|PASS' "$TEAVM_MULTI_SOAK" || fail 'MLE multiplayer soak gate missing'
grep -q 'session pga memory max' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak PGA sampling missing'
grep -q 'PMLE_TEAVM_MULTI_SOAK_SLOW' "$TEAVM_MULTI_SOAK" || fail 'MLE slow-call timestamp evidence missing'
grep -Fq 'v\$active_session_history' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE slow-call ASH correlation missing'
grep -q 'smaps_rollup' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak OS-process sampling missing'
grep -q 'client_identifier' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak exact-session identifier fence missing'
grep -q 'DOOMDB_MLE_SOAK_WARMUP_SECONDS.*300' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak warmup default missing'
grep -q 'DOOMDB_MLE_SOAK_MEMORY_MARGIN_BYTES.*67108864' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak absolute-memory margin missing'
grep -q 'max_rss<=base_rss+margin' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak RSS absolute ceiling missing'
grep -q 'max_pss<=base_pss+margin' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak PSS absolute ceiling missing'
grep -q 'max_private<=base_private+margin' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak private-memory absolute ceiling missing'
grep -q 'action=TICKER' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'MLE soak scored-window memory fence missing'
grep -q 'c_warmup_seconds constant number:=300' "$TEAVM_MULTI_SOAK" || fail 'MLE soak SQL warmup window missing'
grep -q 'PMLE_TEAVM_COOP_DIFFERENTIAL|PASS' "$TEAVM_COOP" || fail 'MLE co-op route differential missing'
grep -q 'doom_teavm_sim_multi_init_skill' "$TEAVM_COOP" || fail 'MLE co-op skill initialization missing'
grep -q 'PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS' "$TEAVM_MEMBERSHIP_DIFF" || fail 'MLE membership recovery differential missing'
grep -q 'doom_mocha_multiplayer_sim_membership_step' "$TEAVM_MEMBERSHIP_DIFF" || fail 'OJVM membership oracle binding missing'
grep -q 'doom_teavm_sim_restore' "$TEAVM_MEMBERSHIP_DIFF" || fail 'MLE membership checkpoint recovery missing'
grep -q 'mle_sha256=' "$TEAVM_MEMBERSHIP_DIFF" || fail 'membership MLE artifact evidence missing'
grep -q 'ojvm_jar_sha256=' "$TEAVM_MEMBERSHIP_DIFF" || fail 'membership OJVM artifact evidence missing'
grep -q 'environment-metadata.sql' "$TEAVM_DIFFERENTIAL_RUNNER" || fail 'differential environment metadata missing'
grep -q 'doom_teavm_sim_multi_init_game' "$TEAVM_SIM_LOADER" || fail 'MLE durable match initializer missing'
grep -q 'initializeMultiplayerGame' "$TEAVM_SIM_LOADER" || fail 'MLE generalized multiplayer export missing'
grep -q 'doom_teavm_sim_authority_step' "$TEAVM_SIM_LOADER" || fail 'MLE authoritative membership step missing'
grep -q 'DeterministicSqrtPropertyTest' "$TEAVM_BUILD" || fail 'deterministic sqrt property gate missing'
grep -q 'IterativeBspTraversalPropertyTest' "$TEAVM_BUILD" ||
  fail 'iterative BSP transformation property gate missing'
grep -q 'PASS ITERATIVE_BSP_TRAVERSAL_PROPERTY' "$TEAVM_BSP_PROPERTY" ||
  fail 'iterative BSP property test lacks a terminal marker'
grep -Fq 'recursiveVisits[visit] != iterativeVisits[visit]' \
  "$TEAVM_BSP_PROPERTY" ||
  fail 'iterative BSP property test does not compare visitation order'
grep -q 'size > nodeCount + 1' "$TEAVM_BSP_PROPERTY" ||
  fail 'iterative BSP property test does not enforce the stack bound'
test "$(grep -c 'if (side == 2) side = 0' "$TEAVM_BSP_PROPERTY")" -eq 2 ||
  fail 'iterative BSP property omits the on-partition start-side rule'
grep -Fq 'endSide[node] = bounded(3)' "$TEAVM_BSP_PROPERTY" ||
  fail 'iterative BSP property omits on-partition ending-side coverage'
grep -q 'emitted Math member is not allowlisted' "$TEAVM_BUILD" || fail 'emitted Math allowlist gate missing'
grep -Fq "Math.imul|Math.floor|Math.ceil|Math.round" "$TEAVM_BUILD" || fail 'exact Math operation allowlist missing'
grep -Fq "rg -F 'Math['" "$TEAVM_BUILD" || fail 'computed Math access fence missing'
grep -q 'Profiler.start' "$TEAVM_PROFILE" || fail 'Node ledger CPU profile missing'
grep -q 'PMLE_LONG_FLAG_CAST|PASS' "$TEAVM_LONG_FLAG_BENCH" &&
  grep -q "raise_application_error(-20796,'flag cast checksum')" \
    "$TEAVM_LONG_FLAG_BENCH" &&
  grep -Fq '[r]un-decps-ledger' "$TEAVM_LONG_FLAG_RUNNER" &&
  grep -q 'oracle-alert-window.sh' "$TEAVM_LONG_FLAG_RUNNER" ||
  fail 'long-flag cast probe is not exact-stream-safe and fail-closed'
grep -q 'MF_SKULLFLY' "$TEAVM_MOBJ_LOW_WORD_PATCH" &&
  grep -q 'MF_COUNTKILL' "$TEAVM_MOBJ_LOW_WORD_PATCH" &&
  grep -q 'flagsLow' "$TEAVM_MOBJ_LOW_WORD_PATCH" &&
  grep -q '1_000_000' "$TEAVM_MOBJ_LOW_WORD_PROPERTY" &&
  grep -q '1L << 38' "$TEAVM_MOBJ_LOW_WORD_PROPERTY" &&
  grep -q 'LongFlagLowWordPropertyTest' "$TEAVM_BUILD" &&
  grep -q 'build-simulation.sh' "$TEAVM_MOBJ_LOW_WORD_RUNNER" &&
  grep -q 'run-javascript-candidate-parity.mjs' \
    "$TEAVM_MOBJ_LOW_WORD_RUNNER" ||
  fail 'mobj low-word candidate lacks boundary/property/parity fencing'
grep -q 'promotion_threshold_pct=5.000' "$TEAVM_MOBJ_LOW_WORD_COMPARE" &&
  grep -q 'REJECT_BELOW_5_PERCENT' "$TEAVM_MOBJ_LOW_WORD_COMPARE" &&
  grep -q 'peak.length, 7' "$TEAVM_MOBJ_LOW_WORD_COMPARE" ||
  fail 'mobj low-word rank comparator lacks predeclared real-MLE threshold'
grep -q '13272' "$TEAVM_PROFILE" || fail 'Node profile ledger-size fence missing'
grep -q 'DOOMDB_TEAVM_MINIFYING' "$TEAVM_BUILD" &&
  grep -q '"-Dteavm.minifying=$minifying"' "$TEAVM_BUILD" ||
  fail 'TeaVM build does not expose a provenance-marked profile shape'
grep -q 'DOOMDB_TEAVM_MINIFYING=false' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'live-dm-2026-07-23' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'tic between 1 and 5250' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'DOOMDB_MLE_PROFILE_OUTPUT' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'PMLE_DECPS_NODE_PROFILE|PASS' "$TEAVM_DECPS_NODE_PROFILE" ||
  fail 'fresh de-CPS peak-stream CPU profile is not reproducible'
grep -q 'verify-mle-warm-lifecycle.sql' "$TEAVM_DECPS_WARM_LIFECYCLE" &&
  grep -q 'oracle-alert-window.sh' "$TEAVM_DECPS_WARM_LIFECYCLE" &&
  grep -q 'PMLE_HOST_QUIESCENCE|PASS' "$TEAVM_DECPS_WARM_LIFECYCLE" ||
  fail 'de-CPS warm lifecycle runner lacks repeatable evidence fencing'
grep -q -- '--self-test' "$TEAVM_DECPS_NODE_PROFILE_RANK" &&
  grep -q 'PMLE_DECPS_NODE_PROFILE_RANK|PASS' \
    "$TEAVM_DECPS_NODE_PROFILE_RANK" &&
  grep -q ">= 25 ? 'YES' : 'NO'" "$TEAVM_DECPS_NODE_PROFILE_RANK" &&
  grep -q 'rank-decps-node-profile.mjs' "$TEAVM_DECPS_NODE_PROFILE" ||
  fail 'de-CPS Node CPU profile lacks a category-ranking self-test'
grep -q 'doomdbSqrtFloat' "$TEAVM_PATCH" || fail 'deterministic float sqrt replacement missing'
grep -q 'doomdbScaledSqrt' "$TEAVM_PATCH" || fail 'deterministic scaled sqrt replacement missing'
grep -q 'InitHeadlessDirectories' "$TEAVM_INIT_DIET_PATCH" ||
  fail 'headless texture directory missing'
grep -q 'createHeadlessAuthority' "$TEAVM_INIT_DIET_PATCH" ||
  fail 'authority-only constructor missing'
grep -q '!authorityHeadless && isRegistered()' "$TEAVM_INIT_DIET_PATCH" ||
  fail 'single WAD authority parse missing'
grep -q 'PMLE_INIT_DIET_STAGING|PASS' "$TEAVM_INIT_DIET_RUNNER" ||
  fail 'init-diet database staging SHA gate missing'
grep -q 'target_ms=30000' "$TEAVM_INIT_DIET_RUNNER" ||
  fail 'init-diet 30 second gate missing'
grep -q -- '--cpu-prof' "$TEAVM_INIT_PROFILE" ||
  fail 'init V8 CPU profile missing'
grep -q 'PMLE_INIT_PROFILE_TS|elapsed_ms=' "$TEAVM_INIT_PROFILE" ||
  fail 'init stdout timestamping missing'
grep -q 'smaps_rollup' "$TEAVM_MEMORY_CAL" || fail 'OS process memory sampler missing'
grep -q 'minimum_visible_bytes' "$TEAVM_MEMORY_CAL" || fail 'known-allocation visibility gate missing'
grep -q 'create mle module doom_mle_memory_cal language javascript' "$TEAVM_MEMORY_CAL_SQL" ||
  fail 'calibration-only MLE module missing'
grep -q 'c_allocation_bytes constant pls_integer:=134217728' "$TEAVM_MEMORY_CAL_SQL" ||
  fail '128 MiB retained allocation calibration missing'
grep -q 'offset += 4096' "$TEAVM_MEMORY_CAL_SQL" ||
  fail 'retained allocation page-touch loop missing'
grep -q "drop mle module doom_mle_memory_cal" "$TEAVM_MEMORY_CAL_SQL" ||
  fail 'calibration-only MLE module cleanup missing'
grep -q 'allocation_bytes=134217728' "$TEAVM_MEMORY_CAL" ||
  fail 'calibration runner byte count differs from SQL calibration'
grep -q 'PMLE_ACTIVE_STATE_DISPATCH' "$TEAVM_DISPATCH_BENCH" || fail 'ActiveStates MLE dispatch benchmark missing'
grep -q 'active-state-dispatch' "$TEAVM_DISPATCH_RUNNER" || fail 'ActiveStates dispatch artifact build missing'
grep -q 'base64_fold_width=2000' "$TEAVM_DISPATCH_RUNNER" || fail 'dispatch safe base64 fold missing'
grep -Fq 'while IFS= read -r piece || [[ -n "$piece" ]]' "$TEAVM_DISPATCH_RUNNER" || fail 'dispatch final base64 piece fence missing'
grep -q 'DISPATCH_SOURCE_GATE|PASS' "$TEAVM_DISPATCH_RUNNER" || fail 'dispatch database staging SHA gate missing'
grep -q 'whenever sqlerror exit sql.sqlcode rollback' "$TEAVM_DISPATCH_RUNNER" || fail 'dispatch fail-closed SQL fence missing'
grep -Fq "pgrep -f '[b]uild-ledger-differential.mjs'" "$TEAVM_DISPATCH_AB" || fail 'dispatch A/B ledger fence missing'
grep -q 'doomdb-pmle-ledger-' "$TEAVM_DISPATCH_AB" ||
  fail 'dispatch A/B does not honor the run-lifetime ledger lock'
grep -q 'PMLE_HOST_QUIESCENCE|PASS' "$TEAVM_DISPATCH_AB" || fail 'dispatch A/B host-quiescence evidence missing'
grep -q 'log_mode=exclusive-create' "$TEAVM_LEDGER_RUNNER" || fail 'ledger no-overwrite provenance missing'
grep -Fq "pgrep -f '[b]uild-ledger-differential.mjs'" "$TEAVM_LEDGER_RUNNER" ||
  fail 'ledger runner does not reject a concurrent promotion ledger'
grep -q 'doomdb-pmle-ledger-' "$TEAVM_LEDGER_RUNNER" ||
  fail 'ledger runner does not hold a run-lifetime lock'
grep -q 'PMLE_LEDGER_RUNTIME' "$TEAVM_LEDGER_RUNNER" ||
  fail 'ledger elapsed-time provenance missing'
grep -q 'PMLE_PINNED_PAIR' "$TEAVM_LEDGER_RUNNER" || fail 'ledger pinned authority/oracle evidence missing'
grep -Fq 'lock.teaVM.outputSha256' "$TEAVM_LEDGER_RUNNER" &&
  grep -Fq 'lock.teaVM.outputBytes' "$TEAVM_LEDGER_RUNNER" ||
  fail 'ledger production authority provenance is not derived from versions.lock'
if grep -q "^pinned_authority='[0-9a-f]" "$TEAVM_LEDGER_RUNNER"; then
  fail 'ledger runner retains a stale hardcoded production authority'
fi
grep -q 'deep-every=1' "$TEAVM_LEDGER_RUNNER" || fail 'ledger every-tic differential missing'
grep -q 'progress-every=100' "$TEAVM_LEDGER_RUNNER" || fail 'ledger progress cadence missing'
grep -q 'environment-metadata.sql' "$TEAVM_DISPATCH_AB" || fail 'dispatch A/B environment metadata missing'
test "$(line_of 'DISPATCH_SOURCE_GATE|PASS' "$TEAVM_DISPATCH_RUNNER")" -lt \
  "$(line_of 'create mle module doom_mle_dispatch' "$TEAVM_DISPATCH_RUNNER")" || fail 'dispatch staging gate runs after module creation'
if sed -n '/public static int stepMultiplayerBare/,/Apply one authoritative/p' "$TEAVM_SIM_SOURCE" | grep -q 'Uint8Array.create'; then
  fail 'dispatch A/B hot path contains an additive worker allocation'
fi
grep -q "ascii(bytes, 0, 4) !== 'DMD1'" "$AUTHORITY_TS" || fail 'DMD1 client envelope fence missing'
grep -q 'authority chain hash is invalid' "$AUTHORITY_TS" || fail 'DMD1 client chain verification missing'
grep -q 'stepMultiplayerAuthoritative' "$AUTHORITY_MIRROR_TS" || fail 'confirmed TeaVM membership-aware mirror step missing'
grep -q 'transition.membershipBitmap' "$AUTHORITY_MIRROR_TS" || fail 'confirmed TeaVM mirror membership fence missing'
grep -q 'requires recovery' "$AUTHORITY_MIRROR_TS" || fail 'confirmed TeaVM mirror recovery fence missing'
grep -q 'DMB1' "$AUTHORITY_BATCH_TS" || fail 'DMB1 client batch decoder missing'
grep -q 'class ConfirmedWanPolicy' "$AUTHORITY_WAN_TS" || fail 'confirmed WAN policy missing'
grep -q 'LEAD_HYSTERESIS_MS = 10_000' "$AUTHORITY_WAN_TS" || fail 'WAN lead hysteresis missing'
grep -q 'MAX_INPUT_LEAD = 12' "$AUTHORITY_WAN_TS" || fail 'WAN lead bound missing'
grep -q 'MAX_PLAYOUT_TICS = 6' "$AUTHORITY_WAN_TS" || fail 'WAN playout bound missing'
grep -q 'server-tic<=25' "$WAN_SOAK" ||
  fail 'WAN startup convergence fence is not pinned to playout plus batch'
grep -q 'transitionHoldMs, 32' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN bounded long-poll client binding missing'
grep -q 'HIDDEN_CHECKPOINT_THRESHOLD_MS = 5_000' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab checkpoint threshold missing'
grep -q "strategy:'poll-lease-released'" "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab poll lease release missing'
grep -q "reason:'confirmed-checkpoint'" "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab checkpoint resync missing'
grep -q 'batch.committedFrontierTic-mirror.frontier.tic+1' \
  "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN input lead is not bound to the confirmed-mirror backlog'
grep -q 'Math.min(1000/140' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN confirmed-mirror apply catch-up ceiling regressed'
grep -q 'confirmedPlayoutDecision(bufferOccupancy,wan.playoutBufferTics' \
  "$ROOT/client/src/multiplayer.ts" &&
  grep -q "mode==='ACCELERATE' && bufferedFrames<=selectedDepth" \
    "$ROOT/client/src/authority-wan.ts" ||
  fail 'WAN confirmed-presentation catch-up latch regressed'
grep -q 'PLAYOUT_ACCELERATION_MARGIN_TICS = 2' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'PLAYOUT_DECELERATION_MARGIN_TICS = 2' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'MAX_DECELERATED_PLAYOUT_INTERVAL_MS = 31.4' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q "mode==='DECELERATE' && bufferedFrames>=selectedDepth" \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'observeConfirmedBatch(nowMs: number, frameCount: number)' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'Math.max(0,nowMs-this.lastBatchDeliveryMs-representedMs)' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'confirmedBatchPlayoutDecision(' \
    "$ROOT/client/src/authority-wan.ts" &&
  grep -q 'batchPolicy.observeConfirmedBatch(0,7)' \
    "$AUTHORITY_WAN_TEST" ||
  fail 'WAN confirmed-presentation setpoint or bounded margins regressed'
grep -q 'MANAGED_ORDS_SESSION_GROWTH_CAP=6' "$WAN_SOAK" &&
  grep -q 'ordsSessionGrowthCap=' "$WAN_SOAK" ||
  fail 'WAN managed-ORDS pooled-session postflight bound regressed'
grep -q 'MAX_PRESENTATION_OCCUPANCY_EXCURSION_MS=5_000' "$WAN_SOAK" &&
  grep -q 'occupancy_excursion_max_ms=' "$WAN_SOAK" &&
  grep -q 'occupancyExcursionMaxMs<=' "$WAN_SOAK" ||
  fail 'WAN bounded confirmed-occupancy excursion gate regressed'
if grep -q 'presentationLag<=64+playout' "$WAN_SOAK"; then
  fail 'WAN phase-dependent instantaneous occupancy assertion returned'
fi
if grep -q 'next.presentation.tic <= target\\|confirmed-backlog\\|MAX_CONFIRMED_PRESENTATION_BACKLOG' \
    "$ROOT/client/src/multiplayer.ts"; then
  fail 'WAN free-running confirmed playout regained a frontier clamp or skip path'
fi
grep -q 'restoreBrowserAuthorityCheckpoint' "$ROOT/client/src/teavm-browser.ts" ||
  fail 'browser DMC1 restore binding missing'
grep -q 'PMLE_WAN_PROXY|READY' "$WAN_PROXY" || fail 'WAN proxy readiness marker missing'
grep -q 'PMLE_WAN_GATE|PASS' "$WAN_SOAK" || fail 'WAN browser acceptance marker missing'
grep -q 'neutral substitution rate' "$WAN_SOAK" || fail 'WAN neutral-substitution gate missing'
grep -q 'input/mirror p95' "$WAN_SOAK" ||
  fail 'WAN input-to-confirmed-mirror gate missing'
grep -q 'DOOMDB_WAN_TRANSPORT_LEGS??1' "$WAN_SOAK" ||
  fail 'WAN topology-aware diagnostic default missing'
grep -q 'queueInput(latest)' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN authored-neutral input heartbeat missing'
grep -q 'never acceptable' "$WAN_SOAK" ||
  fail 'WAN long-poll hold exclusion missing'
grep -q 'presentation p99' "$WAN_SOAK" || fail 'WAN presentation-cadence gate missing'
grep -q 'PMLE_WAN_PLAYOUT|PASS' "$WAN_SOAK" &&
  grep -q 'desired_p90=' "$WAN_SOAK" &&
  grep -q 'confirmed_to_presented_p95_ms=' "$WAN_SOAK" &&
  grep -q 'maxPlayout<=6' "$WAN_SOAK" ||
  fail 'WAN playout amendment cost and low-RTT isolation gates are missing'
grep -Fq 'PMLE_WAN_PRESENTATION_CONTRACT|max_playout_tics=6|low_rtt_max_selected_tics=6|controller=FREE_CLOCK_CONFIRMED_OCCUPANCY_SETPOINT|setpoint=selected_depth|acceleration_margin_tics=2|deceleration_margin_tics=2|max_decelerated_interval_ms=31.4|presentation_lag_p95_formula=selected_max+batch_count_p95+2' \
  "$TEAVM_WAN_RUNNER" ||
  fail 'WAN presentation-cost verdict rule is not predeclared'
grep -q 'PMLE_WAN_STALL_RECOVERY|PASS' "$WAN_SOAK" &&
  grep -q 'maximumObservedTransportStall>=3000' "$WAN_SOAK" &&
  grep -q 'rate<.005' "$WAN_SOAK" ||
  fail 'WAN implicit recovery is not bound to a measured stall and fairness gate'
grep -q 'PMLE_WAN_MATRIX|PASS' "$TEAVM_WAN_RUNNER" || fail 'WAN matrix terminal marker missing'
grep -q 'DOOMDB_WAN_QUALIFICATION:-NO' "$TEAVM_WAN_RUNNER" &&
  grep -q 'wait-free charter approval artifact is absent' \
    "$TEAVM_WAN_RUNNER" &&
  grep -q 'qualification is authorized only for wait-free transport' \
    "$TEAVM_WAN_RUNNER" &&
  grep -q 'qualification may not filter WAN profiles' \
    "$TEAVM_WAN_RUNNER" &&
  grep -q 'classification=QUALIFICATION' "$TEAVM_WAN_RUNNER" &&
  grep -q 'approval_sha256=' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN qualification does not fail closed on charter approval and topology'
grep -q 'DOOMDB_WAN_LONG_POLL_ENABLED:-1' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix long-poll default missing'
grep -q 'DOOMDB_WAN_HOLD_MS:-500' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix bounded hold missing'
grep -q 'DOOMDB_WAN_BACKGROUND_SCENARIO=1' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix background/refocus scenario missing'
grep -q 'PMLE_WAN_TRANSPORT|long_poll=$mode' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix cloud-shaped pool metadata missing'
grep -q 'DOOMDB_MANAGED_ADB=1' "$TEAVM_WAN_RUNNER" &&
  grep -q 'SOAK_ADB_RESOURCE' "$WAN_SOAK" &&
  grep -q 'memoryGate=SEPARATE_RETAINED_SESSION_SOAK' "$WAN_SOAK" ||
  fail 'WAN managed-ADB telemetry contract missing'
grep -q 'PMLE_PREWARM_DECOMPOSITION|PASS' \
  "$ROOT/probes/mle/teavm-engine/run-prewarm-decomposition.sh" ||
  fail 'deploy prewarm composition harness missing'
grep -q 'already exists:' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix no-overwrite evidence fence missing'
grep -q 'environment-metadata.sql' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix environment metadata missing'
grep -q 'artifact-metadata.sql' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix artifact metadata missing'
grep -q 'one outstanding poll per player' "$AUTHORITY_TRANSPORT" || fail 'DMB1 one-poll fence missing'
grep -q 'c_max_held_polls constant pls_integer:=4' "$AUTHORITY_TRANSPORT" || fail 'DMB1 ORDS pool reserve missing'
grep -q 'c_resmgr_running_sessions constant pls_integer:=2' "$AUTHORITY_TRANSPORT" || fail 'DMB1 resource-manager bound missing'
grep -q 'c_max_concurrent_poll_returns constant pls_integer:=1' "$AUTHORITY_TRANSPORT" || fail 'DMB1 runnable reserve missing'
grep -q 'c_max_hold_ms constant pls_integer:=500' "$AUTHORITY_TRANSPORT" || fail 'DMB1 hold bound missing'
grep -q 'c_wan_min_batch_transitions constant pls_integer:=8' "$AUTHORITY_TRANSPORT" || fail 'DMB1 WAN batch floor missing'
grep -q 'exit when l_count>=l_ready_count or elapsed_ms(l_started)>=l_hold' "$AUTHORITY_TRANSPORT" || fail 'DMB1 WAN batch readiness fence missing'
grep -q 'dbms_alert.waitone' "$AUTHORITY_TRANSPORT" || fail 'DMB1 prompt commit alert missing'
grep -q 'doom_match_slow_call' "$ROOT/sql/schema/048_multiplayer_worker.sql" || fail 'worker slow-call schema missing'
grep -q 'record_slow_call' "$ROOT/sql/sim/084_multiplayer_worker.sql" || fail 'worker post-commit slow-call attribution missing'
grep -q "'STANDBY_CHECKPOINT'" "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'standby checkpoint phase attribution missing'
grep -q 'elapsed_micros(l_started,l_restored)/1000' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'standby checkpoint restore attribution missing'
grep -q 'elapsed_micros(l_restored,l_replayed)/1000' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'standby checkpoint replay attribution missing'
grep -q 'elapsed_micros(l_replayed,l_saved)/1000' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'standby checkpoint serialization attribution missing'
grep -q 'if p_warm and l_players=2 and l_deathmatch=0 and l_skill=3' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'default-origin standby restore elision missing'
grep -q 'and l_episode=1 and l_map=1 then' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'default-origin standby restore fence is incomplete'
grep -q 'cpu_sample_tic number(12)' "$ROOT/sql/schema/048_multiplayer_worker.sql" ||
  fail 'authority CPU telemetry schema missing'
grep -q 'procedure sample_authority_cpu' "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'authority CPU telemetry sampler missing'
grep -q 'dbms_utility.get_cpu_time' "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'authority session CPU source missing'
grep -q "set_action('MLE_CHECKPOINT_PREPARE')" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q "set_action('MLE_CHECKPOINT_EXPORT')" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q "set_action('CHECKPOINT_FRAME_FLUSH')" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q 'doom_mle_match_runtime.flush_live_frames(' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q 'doom_mle_match_runtime.prepare_checkpoint' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q 'doom_mle_match_runtime.export_prepared_checkpoint' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'two-phase authority checkpoint liveness actions are missing'
grep -q 'function worker_liveness_suppresses' "$DOOM_API" ||
  fail 'REST checkpoint liveness discriminator missing'
grep -q 'where sid=p_sid and serial#=p_serial' "$DOOM_API" ||
  fail 'REST checkpoint discriminator is not bound to SID+serial'
grep -q "'SUPPRESS_BUSY'" "$DOOM_API" ||
  fail 'REST checkpoint busy lease is not the primary discriminator'
grep -q 'doom_match_liveness_probe' "$DOOM_API" ||
  fail 'REST recovery decisions are not attributed'
grep -q 'c_worker_stale_seconds constant pls_integer := 15' "$DOOM_API" ||
  fail 'REST worker timeout does not clear measured checkpoint duration'
grep -q 'c_worker_probe_seconds constant pls_integer := 5' "$DOOM_API" ||
  fail 'REST busy lease is not probed during measured checkpoint calls'
grep -q "'DEFER_BACKSTOP'" "$DOOM_API" ||
  fail 'REST liveness probe does not distinguish threshold backstop'
grep -q 'run-memory-calibration.sh' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" || fail 'worker soak memory visibility calibration missing'
grep -q 'PMLE_WORKER_SOAK_MEMORY' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" || fail 'worker soak absolute process-memory gate missing'
grep -q 'resmgr:cpu quantum' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" || fail 'worker soak resource-manager attribution missing'
grep -q 'PMLE_WORKER_SOAK_BROWSER_EVIDENCE|BEGIN' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" ||
  fail 'worker soak pre-cleanup browser evidence preservation missing'
grep -q 'reason=unplanned_retained_process_replacement' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" ||
  fail 'worker soak process replacement hard-fail missing'
grep -q 'shared_dirty=' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" ||
  fail 'worker soak shared-SGA attribution missing'
grep -q 'PMLE_WORKER_SOAK|VOIDED|reason=harness_exit' "$ROOT/probes/mle/teavm-engine/run-worker-soak.sh" ||
  fail 'worker soak harness-abort void classification missing'
grep -q 'doom_match_poll_lease' "$AUTHORITY_TRANSPORT_SCHEMA" || fail 'DMB1 poll lease schema missing'
grep -q 'prompt_return_ms' "$AUTHORITY_TRANSPORT_TEST" || fail 'DMB1 prompt-return live gate missing'
grep -q "utl_raw.cast_to_raw('DMD1')" "$AUTHORITY_SQL" || fail 'DMD1 SQL encoder missing'
grep -q 'dbms_crypto.hash' "$AUTHORITY_SQL" || fail 'DMD1 SQL chain missing'
grep -q "utl_raw.cast_to_raw('DMB1')" "$AUTHORITY_TRANSPORT" || fail 'DMB1 batch name drift'
grep -q 'doom_mle_live_init_game' "$MLE_MATCH_RUNTIME" || fail 'MLE worker game initialization missing'
grep -q 'doom_mle_live_step' "$MLE_MATCH_RUNTIME" || fail 'MLE worker authoritative step missing'
grep -q 'doom_mle_live_checkpoint_chunk' "$MLE_MATCH_RUNTIME" || fail 'MLE worker checkpoint export missing'
grep -q 'doom_mle_live_restore_load' "$MLE_MATCH_RUNTIME" || fail 'MLE worker checkpoint recovery missing'
grep -q 'doom_mle_live_restore_warm' "$MLE_MATCH_RUNTIME" ||
  fail 'fail-closed warm MLE checkpoint restore missing'
grep -q 'create mle env doom_mle_live_env imports' "$MLE_LIVE_FRAME_LOADER" ||
  fail 'live-frame coordinator environment missing'
grep -q "live-frame authority source mismatch" "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'live.authorityCandidateSha256' "$MLE_LIVE_FRAME_LOADER" ||
  fail 'live-frame environment is not fenced to its authority artifact'
grep -Fq 'lock="${PMLE_LIVE_FRAME_LOCK:-$root/versions.lock}"' \
  "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'candidate live-frame lock requires PMLE_LIVE_FRAME_CANDIDATE=YES' \
  "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'ACTIVE_LIVE_CONTEXTS=' "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'live-frame module deployment requires the retained pool parked' \
  "$MLE_LIVE_FRAME_LOADER" ||
  fail 'diagnostic live-frame pin override is not explicit/fail-closed'
grep -q "signature 'renderAndPublishMatchFrame" "$MLE_LIVE_FRAME_LOADER" ||
  fail 'live-frame render/publish call spec missing'
grep -q "signature 'prepareMatchViews" "$MLE_LIVE_FRAME_LOADER" &&
grep -q "signature 'publishPreparedMatchViews" "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'doom_mle_match_runtime.prepare_views' "$MLE_MATCH_WORKER" &&
grep -q 'doom_mle_match_runtime.publish_prepared_views' "$MLE_MATCH_WORKER" &&
grep -q 'create table doom_match_frame_stage_window' \
  "$MLE_FRAME_STAGE_SCHEMA" ||
  fail 'two-POV render/publication stage decomposition is not fenced'
grep -q 'renderAndPublishMatchFrame' "$MLE_LIVE_FRAME_COORDINATOR" ||
  fail 'live-frame coordinator pipeline missing'
node "$ROOT/tests/verify-temporal-static-copy.mjs" >/dev/null ||
  fail 'stationary confirmed-frame bulk-copy equivalence failed'
node --check "$MLE_RENDERER_ASSET_PACK_BUILDER" >/dev/null ||
  fail 'renderer asset-pack builder syntax is invalid'
(
  asset_tmp=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-asset-pack.XXXXXX")
  trap 'rm -rf "$asset_tmp"' EXIT
  node "$MLE_RENDERER_ASSET_PACK_BUILDER" "$ROOT" "$asset_tmp" >/dev/null
  for kind in wall_texture flat sprite_patch ui_patch; do
    cmp "$asset_tmp/$kind.bin" \
      "$ROOT/probes/mle/target/free-live-renderer/assets-v1/$kind.bin"
  done
) || fail 'renderer asset packs do not match the canonical seed manifest'
test "$(grep -Fc 'renderer.resetPresentationState() !== 10' \
  "$MLE_LIVE_FRAME_COORDINATOR")" -eq 5 ||
  fail 'live-frame coordinator does not reset retained presentation state'
grep -q 'const MATCH_LIVE_BATCH_FRAMES = 2' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'update doom_match_live_frame_batch' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'payload_blob=empty_blob(),published_at=systimestamp' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -Fq 'state.bytes.set([68, 80, 66, 50], 0)' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'changed || state.count === MATCH_LIVE_BATCH_FRAMES' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'flushMatchLiveFrameBatches' "$MLE_LIVE_FRAME_COORDINATOR" ||
  fail 'two-frame persistent DPB2 locator publication missing'
grep -q 'presentationWorldGeometryAndSidesSnapshotLength' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'renderCompleteMatchFrame(playerSlot, changed, frameTic)' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'Seed every match/generation once with the full DVL2 world snapshot' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'Apply both before the first render' "$MLE_LIVE_FRAME_COORDINATOR" &&
perl -0777 -ne 'exit !(/if \(fullWorld\).*?prepareCurrentSnapshot\(playerSlot, true\);.*?loadPreparedDynamics\(\);.*?prepareCurrentSnapshot\(playerSlot, false\);.*?loadPreparedDynamics\(\);/s)' \
  "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'renderer.resetWorldState() < 1' "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'baselineSectorFloor = sectorFloor.clone()' "$MLE_LIVE_WORLD_BUILDER" &&
grep -q 'baselineSideRowOffset = dynamicSideRowOffset.clone()' \
  "$MLE_LIVE_WORLD_BUILDER" &&
grep -q 'public static int resetDynamicWorldState()' \
  "$MLE_LIVE_WORLD_BUILDER" &&
grep -q 'return FreeLiveWorldRasterCore.resetDynamicWorldState()' \
  "$MLE_LIVE_UNIFIED_MODULE" ||
  fail 'new retained assignments do not seed full renderer world state'
grep -q 'paletteIndexFromSnapshot' "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'snapshotI32(snapshot, 128)' "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'snapshotI32(snapshot, 132)' "$MLE_LIVE_FRAME_COORDINATOR" &&
grep -q 'appendMatchLiveFrame(state, frameTic, retainedPaletteIndex)' \
  "$MLE_LIVE_FRAME_COORDINATOR" ||
  fail 'authoritative damage/bonus PLAYPAL selection is not published'
grep -q 'create table doom_match_live_frame' "$MLE_LIVE_FRAME_SCHEMA" &&
grep -q 'create table doom_match_live_frame_batch' "$MLE_LIVE_FRAME_SCHEMA" &&
grep -q 'frame_count between 1 and 6' "$MLE_LIVE_FRAME_SCHEMA" &&
grep -Fq 'payload_bytes=8+frame_count*64008' "$MLE_LIVE_FRAME_SCHEMA" ||
  fail 'bounded live-frame ring schema missing'
grep -q 'authority_bytes number(10) not null' "$MLE_LIVE_FRAME_SCHEMA" &&
grep -q 'authority_sha256 varchar2(64) not null' "$MLE_LIVE_FRAME_SCHEMA" &&
grep -q "regexp_like(authority_sha256,'\\^\\[0-9a-f\\]{64}\\$')" \
  "$MLE_LIVE_FRAME_SCHEMA" ||
  fail 'live-frame deployed-authority provenance is not schema-fenced'
grep -Fq "and authority_sha256='\$authority_sha'" \
  "$MLE_LIVE_FRAME_LOADER" &&
grep -q 'and authority_bytes=$authority_bytes' "$MLE_LIVE_FRAME_LOADER" ||
  fail 'live-frame loader does not bind staged authority provenance'
grep -q 'ring_slot between 0 and 127' "$MLE_LIVE_FRAME_SCHEMA" ||
  fail 'live-frame ring bound missing'
grep -q 'palette_index number(2) default 0 not null' \
  "$MLE_LIVE_FRAME_SCHEMA" &&
grep -q 'palette_index between 0 and 13' "$MLE_LIVE_FRAME_SCHEMA" ||
  fail 'live-frame PLAYPAL selector is not schema-fenced'
grep -q 'procedure advance_generation' "$MLE_LIVE_FRAME_TRANSPORT" ||
  fail 'live-frame recovery generation fence missing'
grep -q 'procedure poll_match_pixels' "$DOOM_API" ||
  fail 'authenticated live-frame REST procedure missing'
grep -q "'PLAYPAL','PLAYPAL_ALL','TITLEPIC'" "$DOOM_API" &&
grep -q "p_asset_name='PLAYPAL_ALL'" "$DOOM_API" &&
grep -q "l_lump_size<>14\\*256\\*3" "$DOOM_API" &&
grep -q 'PLAYPAL set integrity mismatch' "$DOOM_API" &&
grep -q "request('ASSET_PLAYPAL_ALL','GET_ASSET'" \
  "$ROOT/scripts/t11.1-cloud-api.mjs" &&
grep -q '3d6069acf11e7c8cf6ae77869a3b67eade15c5df686ca3a49fa31e4517359312' \
  "$ROOT/scripts/t11.1-cloud-api.mjs" &&
grep -q 'api.observations.length,20' \
  "$ROOT/scripts/t11.1-build-evidence.mjs" ||
  fail 'full PLAYPAL asset endpoint is absent or not integrity-fenced'
grep -q 'procedure poll_match_pixel_batch' "$DOOM_API" &&
grep -q 'procedure touch_match_presence' "$DOOM_API" &&
grep -q 'procedure ensure_pixel_worker' "$DOOM_API" &&
test "$(grep -c 'procedure ensure_pixel_worker(' "$DOOM_API")" -eq 1 &&
test "$(grep -n -m1 'create or replace package body doom_api as' "$DOOM_API" |
  cut -d: -f1)" -lt \
  "$(grep -n -m1 'procedure ensure_pixel_worker(' "$DOOM_API" |
    cut -d: -f1)" &&
grep -q "p_generation,'PIXEL_POLL'" "$DOOM_API" &&
grep -q 'doom_match_worker.recover_match(p_match,20,l_recovery_state)' \
  "$DOOM_API" &&
test "$(grep -c 'if p_after_tic>=p_current_tic then' "$DOOM_API")" -eq 2 &&
test "$(grep -c 'ensure_pixel_worker(' "$DOOM_API")" -eq 5 &&
grep -q 'p_ready=0 and p_current_tic>0 and p_after_tic<p_current_tic' \
  "$DOOM_API" &&
grep -q 'p_frame_count=0 and p_current_tic>0' "$DOOM_API" &&
perl -0777 -ne 'exit !(/create or replace package body doom_api as.*?\n  procedure poll_match_pixels\(.*?l_slot:=player_capability_slot\(p_match,p_player_capability\);.*?ensure_pixel_worker\(.*?(?=\n  procedure)/s)' \
  "$DOOM_API" &&
perl -0777 -ne 'exit !(/create or replace package body doom_api as.*?\n  procedure poll_match_pixel_batch\(.*?l_slot:=player_capability_slot\(p_match,p_player_capability\);.*?ensure_pixel_worker\(.*?(?=\n  procedure)/s)' \
  "$DOOM_API" &&
perl -0777 -ne 'exit !(/\n  procedure poll_match_pixels\(.*?last_seen_at=l_now.*?commit;.*?ensure_pixel_worker\(.*?doom_mle_live_frame_transport\.poll_latest/s)' \
  "$DOOM_API" &&
perl -0777 -ne '
  /create or replace package body doom_api as.*?(\n  procedure poll_match_pixel_batch\(.*?)(?=\n  procedure|\n  \$if)/s or exit 1;
  $body=$1;
  exit 1 if $body=~/update doom_match_member|renew_match_lease|commit;/;
  exit !($body=~/select count\(\*\) into l_member_valid/
    &&$body=~/doom_mle_live_frame_transport\.poll_batch/s);
' "$DOOM_API" &&
perl -0777 -ne '
  exit !(/\n  procedure touch_match_presence\(.*?update doom_match_member
.*?renew_match_lease\(p_match,l_now\);.*?commit;/s)
' "$DOOM_API" &&
grep -q 'touchMatchPresence(value.match,value.playerCapability)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'window.setInterval(touchPresence,1_000)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'p_after_tic: 2_147_483_647' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'invalid capability changed pixel-worker recovery state' \
  "$MLE_LIVE_FRAME_E2E" &&
grep -q 'procedure poll_batch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q "hextoraw('44504232'" "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'dbms_lob.getlength(l_batch)<>8+l_batch_count*64008' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'p_payload:=l_batch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'l_source_offset:=9+l_skip*64008' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'coalesce(max(latest_.tic),-1)-64' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'ring-gap resync without a permanent ORA-20796 loop' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq "dbms_lob.substr(payload_blob,4,1)=hextoraw('44504431')" \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'foreign-format row entered DPD1 fallback' \
  "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -Fq 'multi_locator_batch=PASS' "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -Fq 'palette_temporal=PASS' "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -q 'dbms_lob.copy(' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq '8+p_frame_count*64008' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'procedure encode_gzip_dpb2' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'utl_compress.lz_compress(l_raw_payload,1)' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'GZIP_DPB2_V1 encoding failed' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q "hextoraw('44505632')" "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'persistent DPV2 header mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'persistent DPV2 record mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'assembled DPV2 batch mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'persistent DPV2 sequence mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'procedure materialize_temporal_bundle' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'persistent EPT1 header mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'l_player_mask not in(1,2,3)' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'l_interval not between 2 and 5' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -Fq 'case when l_view_bundle_mask=3' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'utl_raw.bit_or(' "$MLE_LIVE_FRAME_TRANSPORT" &&
grep -q 'materialized DPV2 length mismatch' "$MLE_LIVE_FRAME_TRANSPORT" &&
perl -0777 -ne 'exit !(/DPV2 amortizes.*?for l_bundle in \(.*?exit when p_frame_count>=p_max_frames;.*?if p_frame_count>0 then.*?DPD1 is the immediate/s)' \
  "$MLE_LIVE_FRAME_TRANSPORT" &&
! grep -q 'select count(\*) into p_frame_count' \
  "$MLE_LIVE_FRAME_TRANSPORT" ||
  fail 'persistent DPB2 batch/suffix transport contract missing'
test "$(grep -c "last_seen_at<l_now-numtodsinterval(1,'SECOND')" \
  "$DOOM_API")" -eq 1 ||
  fail 'legacy single-frame poll lease write is not throttled'
perl -0777 -ne 'exit !(/\n  procedure revise_match_input\(.*?select ticcmd_raw,effective_tic into l_existing,p_effective_tic.*?input revision mismatch.*?update doom_match_member set member_state='\''ACTIVE'\'',last_seen_at=l_now,.*?disconnected_at=null.*?renew_match_lease\(p_match,l_now\);p_accepted:=1;commit;return;/s)' \
  "$DOOM_API" ||
  fail 'idempotent fused-input retry does not preserve member liveness'
grep -q 'doom_mle_match_runtime.render_and_publish' "$MLE_MATCH_WORKER" ||
  fail 'worker live-frame render/publication missing'
perl -0777 -ne 'exit !(/procedure publish_initial\(.*?initialize_ring\(.*?Never publish that pre-ticker presentation state: tic 1.*?update doom_match set match_state=\x27ACTIVE\x27/s)' \
  "$MLE_MATCH_WORKER" &&
grep -q 'if l_tic>l_checkpoint_tic then' "$MLE_MATCH_WORKER" ||
  fail 'worker publishes checkpoint presentation before a ticker refresh'
grep -q 'doom_mle_match_runtime.flush_live_frames' "$MLE_MATCH_WORKER" &&
grep -q 'MLE_RECOVERY_REUSE_RETAINED_CHECKPOINT' "$MLE_MATCH_WORKER" &&
grep -q 'MLE_RECOVERY_COLD_CHECKPOINT_FALLBACK' "$MLE_MATCH_WORKER" &&
grep -q 'restore_checkpoint_recovery' "$MLE_MATCH_WORKER" &&
grep -q 'p_render_prewarm in boolean' "$MLE_MATCH_RUNTIME" &&
grep -q 'cold recovery fallback failed checkpoint=' "$MLE_MATCH_WORKER" &&
grep -q 'where match_id=p_match and tic=l_runtime_tic' \
  "$MLE_MATCH_WORKER" &&
grep -Fq "standby_status in('READY','PROMOTING')" \
  "$MLE_MATCH_WORKER" &&
grep -q 'Persist its stage decomposition' "$MLE_MATCH_WORKER" &&
grep -Fq "'state=current|gametic='||to_char(l_checkpoint_tic)||'|%'" \
  "$MLE_MATCH_WORKER" &&
grep -q 'doom_mle_live_frame_prewarm(600)' "$MLE_MATCH_RUNTIME" &&
grep -q 'l_ticker_prewarm_vector:=hextoraw(' "$MLE_MATCH_WORKER" &&
grep -q '2,3,l_preload_tic,l_ticker_prewarm_vector' "$MLE_MATCH_WORKER" &&
grep -Fq 'doom_mle_match_runtime.restore_checkpoint(' \
  "$MLE_MATCH_WORKER" &&
grep -Fq "status_field(l_status,'gametic')<>'0'" \
  "$MLE_MATCH_RUNTIME" &&
grep -q "sys_context('USERENV','CLOUD_SERVICE') is not null" \
  "$MLE_MATCH_RUNTIME" ||
  fail 'batch flush or cloud renderer plateau prewarm missing'
grep -q 'function authority_sha256 return varchar2' "$MLE_MATCH_RUNTIME" &&
grep -q 'from doom_mle_live_frame_source source_' "$MLE_MATCH_RUNTIME" &&
grep -q 'l_authority_sha:=authority_sha256' "$MLE_MATCH_RUNTIME" &&
grep -q 'l_authority_sha:=doom_mle_match_runtime.authority_sha256' \
  "$MLE_MATCH_WORKER" &&
test "$(grep -h -o 'authority_sha256=l_authority_sha' \
  "$MLE_MATCH_RUNTIME" "$MLE_MATCH_WORKER" | wc -l | tr -d '[:space:]')" \
  -eq 2 &&
! grep -q \
  "authority_sha256=[[:space:]]*'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'" \
  "$MLE_MATCH_RUNTIME" "$MLE_MATCH_WORKER" ||
  fail 'warm checkpoint selection is not bound to deployed authority provenance'
grep -q 'l_render_member.player_slot' "$MLE_MATCH_WORKER" &&
! grep -q 'for l_player in 0..l_render_players-1' "$MLE_MATCH_WORKER" ||
  fail 'worker live-frame POV selection assumes dense membership slots'
! grep -q "standard_hash('\\[\\]'" "$MLE_MATCH_WORKER" &&
test "$(grep -c '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945' \
  "$MLE_MATCH_WORKER")" -eq 4 ||
  fail 'per-tic invariant empty-event SHA still uses the SQL engine'
grep -q 'await startDatabaseFrameGame(local, latestStatus)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'exchangeMatchPixelBatch(' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'decodeDatabasePixelTransport' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'createDatabaseIndexedPaletteBlitter' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "getAsset('PLAYPAL_ALL')" "$ROOT/client/src/multiplayer.ts" &&
grep -q 'if(!transportEstablished)' "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'batch[0]!.tic!==expectedTic' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'cause instanceof MatchCapacityError' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "reason:'generation'" "$ROOT/client/src/multiplayer.ts" &&
grep -q "reason:'ring-gap'" "$ROOT/client/src/multiplayer.ts" &&
grep -q 'serverTic=result.currentTic' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'if(result.generation>requestGeneration)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'lastFrameBatchAt+1000/35-finished' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'wan.observeConfirmedBatch(finished,batch.length)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const wan=new ConfirmedWanPolicy(6,6)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const pixelInputCatchupFloor=3' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'activePixelInputCatchupFloor=finished-started>80' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'frames.size>activePixelInputCatchupFloor' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const pixelPollBatchDelayMs=35' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const interval=databasePixelPlayoutIntervalMs(' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "reason:'effective-input-catchup'" \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'confirmedInputCatchupCursor(' \
  "$ROOT/client/src/multiplayer.ts" &&
! grep -q 'pendingPixelSeek\\|effective-input-seek\\|futureGap' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'Do not seek the transport into a future effective tic' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const confirmedCatchupTic=confirmedInputCatchupCursor(' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'requiresPresentationCatchup(lastEffectiveCommand,input.command)' \
  "$ROOT/client/src/multiplayer.ts" &&
! grep -Fq 'previous.fire' "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'lastEffectiveCommand=null' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'presentedTic=catchupTic' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const MULTIPLAYER_DATABASE_FRAME_INTERVAL_MS = 30' \
  "$ROOT/client/src/authority-wan.ts" &&
grep -q 'const MULTIPLAYER_DATABASE_FRAME_DECELERATED_MS = 31.4' \
  "$ROOT/client/src/authority-wan.ts" &&
grep -q "databasePixelPlayoutIntervalMs(false,'FREE',false),30" \
  "$ROOT/tests/verify-authority-wan.mjs" &&
grep -q 'const pixelInputCatchupFloor=3' \
  "$ROOT/client/src/multiplayer.ts" &&
! grep -q 'decelerationPhase\|interval=.*53' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const hedgeDelayMs=750' "$ROOT/client/src/api.ts" &&
grep -Fq "Promise.any([primaryRequest,hedgeRequest])" \
  "$ROOT/client/src/api.ts" &&
grep -Fq 'primary.abort();hedge.abort()' "$ROOT/client/src/api.ts" &&
grep -q 'frames.size>wan.playoutBufferTics' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q '+wan.expectedConfirmedBatchTics)return' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const pixelInputLeadTics=1' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'const refillFloor=wan.playoutBufferTics' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq '? (frames.size<=refillFloor?8:pixelPollBatchDelayMs)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "set_action('MLE_TICKER_PREWARM')" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q 'for l_preload_tic in 1..600 loop' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -Fq '2,3,l_preload_tic,l_ticker_prewarm_vector' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -q "set_action('MLE_TICKER_RESTORE_ORIGIN')" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -Fq '2,0,3,1,1,0,l_warm_checkpoint,l_state' \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
perl -0777 -ne 'exit !(/if\(changed\) \{.*?urgentPixelInput=true;.*?schedulePixelPolls\(0\);.*?\}/s)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'let urgentPixelInput=false' "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'if(playoutStarted&&!urgentPixelInput' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'frames.size>wan.playoutBufferTics' \
  "$ROOT/client/src/multiplayer.ts" &&
! grep -Fq 'pendingInput===null&&!inputPosting)queueInput(latest)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'Presence has a dedicated one-Hz lifecycle leg' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'const sequence=pendingInput?.sequence??inputSequence+1' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'const input=retryInput??pendingInput;' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'if(urgentPixelInput' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq '&&(pendingInput!==null||retryInput!==null||inputPostInFlight))' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'Input owns the next Free-tier API lane' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'retryInput=input' "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'const changedInput=input.hex!==lastEffectiveInputHex;' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'if(playoutStarted&&changedInput&&presentationCatchup)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'void reviseMatchInput(' "$ROOT/client/src/multiplayer.ts" &&
grep -Fq "throw new Error('input-free database-frame exchange changed')" \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'value.match,value.playerCapability,requestAfterTic,8)' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'confirmedDropTics.has(expected)' \
  "$ROOT/tests/verify-p13.3-multiplayer-client.mjs" &&
grep -Fq 'expected=nextDatabaseFrameTic(expected)' \
  "$ROOT/tests/verify-p13.3-multiplayer-client.mjs" &&
grep -Fq 'return tic+1;' "$ROOT/client/src/pixel-batch.ts" &&
! grep -q 'DATABASE_FRAME_MODULUS\|c_live_render_modulus' \
  "$ROOT/client/src/pixel-batch.ts" \
  "$ROOT/sql/sim/084_multiplayer_worker.sql" &&
grep -Fq 'l_view.tic<>p_last_tic+1' \
  "$ROOT/sql/sim/089_mle_live_frame_transport.sql" &&
grep -q 'wan.playoutBufferTics+wan.expectedConfirmedBatchTics' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'confirmedBatchPlayoutDecision(' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "trace('pixel-starvation'" "$ROOT/client/src/multiplayer.ts" &&
grep -Fq "playoutStarted=true;" "$ROOT/client/src/multiplayer.ts" &&
grep -Fq "playoutMode='DECELERATE';" "$ROOT/client/src/multiplayer.ts" &&
grep -Fq "firstTic:batch[0]!.tic,lastTic:batch.at(-1)!.tic" \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q "reason:'visibility',hiddenMilliseconds" \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'const requestEpoch=pixelPollEpoch' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'if(requestEpoch!==pixelPollEpoch||stopped||suspended)return' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'pixelPollEpoch+=1' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'pixelPollInFlight.clear()' "$ROOT/client/src/multiplayer.ts" &&
grep -q 'paintedAt.length=0;lastFrameBatchAt=0' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -q 'payload.subarray(offset,offset+FRAME_BYTES)' \
  "$MLE_PIXEL_BATCH_SOURCE" &&
grep -q 'pixel batch palette field is invalid' "$MLE_PIXEL_BATCH_SOURCE" &&
grep -q 'pixel batch tics are not consecutive' "$MLE_PIXEL_BATCH_SOURCE" ||
  fail 'production client is not a database-frame canvas consumer'
post_input_source=$(sed -n \
  '/const postInput=():void=>{/,/const pump=():void=>{/p' \
  "$ROOT/client/src/multiplayer.ts")
test "$(printf '%s\n' "$post_input_source" |
  grep -c 'generation=result.generation')" -eq 1 &&
printf '%s\n' "$post_input_source" |
  perl -0777 -ne \
    'exit !(/if\(result\.generation>generation\) \{\s*generation=result\.generation;\s*resetPixelTransport\(\);\s*\}/s)' ||
  fail 'database-frame input response bypasses the generation reset'
grep -Fq "lastEffectiveInputTic=result.effectiveTic" \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq 'lastInputRoundTripMs=finished-started' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq '`tic ${lastEffectiveInputTic} · ${lastInputRoundTripMs.toFixed(0)} ms`' \
  "$ROOT/client/src/multiplayer.ts" &&
grep -Fq '`\nINPUT ${command} · ${effective}`' \
  "$ROOT/client/src/multiplayer.ts" ||
  fail 'database-frame HUD does not expose authoritative input effectiveness'
for built_pixel_batch in "$MLE_PIXEL_BATCH_STAGING" "$MLE_PIXEL_BATCH_DIST"; do
  test -s "$built_pixel_batch" &&
  grep -Eq '0x44504232|1146110514' "$built_pixel_batch" &&
  grep -q 'pixel batch palette field is invalid' "$built_pixel_batch" &&
  grep -q 'pixel batch tics are not consecutive' "$built_pixel_batch" ||
    fail "compiled DPB2 decoder is stale or absent: $built_pixel_batch"
done
node "$AUTHORITY_WAN_TEST" >/dev/null ||
  fail 'compiled confirmed WAN/batched-frame behavior failed'
for built_multiplayer in \
    "$ROOT/client/staging/multiplayer.js" \
    "$ROOT/client/dist/play/multiplayer.js"; do
  grep -q 'exchangeMatchPixelBatch' "$built_multiplayer" &&
  grep -q 'createDatabaseIndexedPaletteBlitter' "$built_multiplayer" &&
  grep -q 'PLAYPAL_ALL' "$built_multiplayer" &&
  grep -q "reason: 'generation'" "$built_multiplayer" &&
  grep -q "reason: 'ring-gap'" "$built_multiplayer" ||
    fail "compiled database-frame client is stale: $built_multiplayer"
done
grep -Fq '1*200+2' "$MLE_COLUMN_MAJOR_TEST" &&
grep -Fq '2*320+1' "$MLE_COLUMN_MAJOR_TEST" &&
grep -q 'createColumnMajorIndexedPaletteBlitter' "$MLE_COLUMN_MAJOR_TEST" &&
grep -q 'paletteBlit(indices,13)' "$MLE_COLUMN_MAJOR_TEST" ||
  fail 'column-major PLAYPAL-aware database framebuffer gate missing'
grep -Fq 'function playerCamera(api)' "$MLE_TEMPORAL_SOLO_TEST" &&
grep -Fq "'held forward command did not move the authoritative player'" \
  "$MLE_TEMPORAL_SOLO_TEST" &&
grep -Fq "'held turn command did not rotate the authoritative player'" \
  "$MLE_TEMPORAL_SOLO_TEST" ||
  fail 'temporal coordinator does not gate authoritative movement and turning'
node --check "$MLE_TEMPORAL_VIEW_BUNDLE_PATCHER" >/dev/null &&
node --check "$MLE_NATIVE_TEMPORAL_PATCHER" >/dev/null &&
node --check "$MLE_STAGGERED_MULTIVIEW_PATCHER" >/dev/null &&
grep -Fq 'DPV2_COMBINED_TEMPORAL_AND_POV' \
  "$MLE_TEMPORAL_VIEW_BUNDLE_PATCHER" &&
grep -Fq 'EPT1_NATIVE_EXACT_DPV2' "$MLE_TEMPORAL_SOLO_TEST" &&
grep -Fq 'EPT1_STAGGERED_MASKED_DPV2' "$MLE_TEMPORAL_SOLO_TEST" &&
grep -Fq 'materialize_temporal_bundle' "$MLE_NATIVE_TEMPORAL_PATCHER" &&
grep -Fq '55d86b81e6e76ee4416622a59052526481ff2d14536b68f2535ca291b246d85b' \
  "$MLE_STAGGERED_MULTIVIEW_PATCHER" &&
grep -Fq "const [inputPath, outputPath, intervalArgument = '4']" \
  "$MLE_STAGGERED_MULTIVIEW_PATCHER" &&
grep -Fq "if (![4,5].includes(staggeredInterval)" \
  "$MLE_STAGGERED_MULTIVIEW_PATCHER" &&
grep -Fq 'const playerOneReseedInterval = staggeredInterval - 2;' \
  "$MLE_STAGGERED_MULTIVIEW_PATCHER" &&
grep -Fq 'renderCompleteMatchFrame(1);' \
  "$MLE_STAGGERED_MULTIVIEW_PATCHER" &&
grep -Fq 'PMLE_NATIVE_TEMPORAL_SYNTHESIS|PASS' \
  "$MLE_NATIVE_TEMPORAL_BENCH" &&
grep -Fq 'PMLE_DPV2_TRANSPORT|PASS' "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -Fq 'ept1_native_exact=PASS' "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -Fq 'stagger_mask2=PASS|intervals=2,3,4,5' \
  "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" &&
grep -Fq 'malformed DPV2 did not fail closed' \
  "$MLE_TEMPORAL_VIEW_BUNDLE_TEST" ||
  fail 'combined temporal/two-POV locator contract is absent or unfenced'
grep -Fq "await page.keyboard.down('ArrowUp')" "$MLE_PUBLIC_MOVEMENT_GATE" &&
grep -Fq 'changedPixels.filter(value=>value>=1_000)' \
  "$MLE_PUBLIC_MOVEMENT_GATE" &&
grep -Fq "'held-arrow route did not paint enough distinct canvas buffers'" \
  "$MLE_PUBLIC_MOVEMENT_GATE" &&
grep -Fq "'ArrowUp did not reach an effective authoritative input revision'" \
  "$MLE_PUBLIC_MOVEMENT_GATE" ||
  fail 'public framebuffer gate does not prove material ArrowUp canvas motion'
if grep -q 'await startMleGame(local, latestStatus)' \
    "$ROOT/client/src/multiplayer.ts"; then
  fail 'production admission still selects browser-side rasterization'
fi
grep -q 'PMLE_LIVE_FRAME_E2E|PASS' "$MLE_LIVE_FRAME_E2E" &&
[[ -x "$ADB_ADMIN_SQL" ]] && bash -n "$ADB_ADMIN_SQL" &&
grep -Fq 'DOOMDB_DB_ADMIN_SQL_CLIENT' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'ADB_ADMIN_PASSWORD' "$ADB_ADMIN_SQL" &&
grep -q 'invalid_capability=REJECTED' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'batch=DPB2x6' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq "import {gunzipSync} from 'node:zlib';" "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'const seedBytes = decodeBatchTransport(seed.p_payload);' \
  "$MLE_LIVE_FRAME_E2E" &&
grep -q "toString('ascii'), 'DPB2'" "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'assert.ok(seed.p_first_tic>=1);' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'seed.p_last_tic,seed.p_first_tic+seed.p_frame_count-1' \
  "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'seedBytes.readUInt32BE(8),seed.p_first_tic' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'const initialWindowLastTic=seed.p_first_tic+6;' \
  "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'while(batchCursor<initialWindowLastTic)' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'assert.equal(logicalFrames.length,6)' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'assert.equal(batchBytes.length,8+batch.p_frame_count*64_008)' \
  "$MLE_LIVE_FRAME_E2E" &&
grep -q 'assert.equal(initialBytes.length, 64_000)' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'const movementTic=input.p_effective_tic;' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'assert.ok(movedChangedPixels>=1_000' "$MLE_LIVE_FRAME_E2E" ||
  fail 'live-frame authenticated moving-frame behavioral gate missing'
grep -Fq 'moved_changed_pixels=${movedChangedPixels}' \
  "$MLE_LIVE_FRAME_E2E" ||
  fail 'live-frame movement evidence does not report material pixel changes'
grep -q 'function readArtifactTuple()' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'dbms_crypto.hash(' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'l_authority,dbms_crypto.hash_sh256' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'l_renderer,dbms_crypto.hash_sh256' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'l_coordinator,dbms_crypto.hash_sh256' "$MLE_LIVE_FRAME_E2E" &&
grep -q "raise_application_error(-20000,'live-frame artifact SHA mismatch')" \
  "$MLE_LIVE_FRAME_E2E" &&
grep -q 'authority_sha256=${artifacts.authoritySha}' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'renderer_sha256=${artifacts.rendererSha}' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'coordinator_sha256=${artifacts.coordinatorSha}' \
  "$MLE_LIVE_FRAME_E2E" ||
  fail 'live-frame runtime evidence is not bound to database-hashed artifacts'
test "$(grep -c 'created.p_player_capability' "$MLE_LIVE_FRAME_E2E")" -ge 4 &&
! grep -q 'created.p_playerCapability' "$MLE_LIVE_FRAME_E2E" ||
  fail 'live-frame soak capability binding is stale'
grep -q 'refusing to overwrite live-frame evidence' \
  "$MLE_LIVE_FRAME_E2E_RUNNER" &&
grep -q 'PMLE_LIVE_FRAME_E2E_EVIDENCE|PASS' \
  "$MLE_LIVE_FRAME_E2E_RUNNER" ||
  fail 'live-frame behavioral evidence runner is not fail-closed'
grep -q 'DOOMDB_LIVE_FRAME_RECOVERY=YES' "$MLE_LIVE_FRAME_RECOVERY" &&
grep -q 'refusing to overwrite pixel-recovery evidence' \
  "$MLE_LIVE_FRAME_RECOVERY" &&
grep -q 'PMLE_LIVE_FRAME_RECOVERY_EVIDENCE|PASS' \
  "$MLE_LIVE_FRAME_RECOVERY" &&
grep -q 'PMLE_PIXEL_RECOVERY_KILL|PASS' "$MLE_LIVE_FRAME_E2E" &&
grep -Fq 'pixelRecoveryResult=`GENERATION_${recovered.p_generation}`' \
  "$MLE_LIVE_FRAME_E2E" ||
  fail 'database-pixel recovery trigger lacks an adversarial runtime gate'
grep -q 'refusing to overwrite DPB2 soak evidence' \
  "$MLE_LIVE_FRAME_TRANSPORT_SOAK" &&
grep -q 'from v[$]temporary_lobs' "$MLE_LIVE_FRAME_TRANSPORT_SOAK" &&
grep -q 'PMLE_DPB2_SOAK|PASS' "$MLE_LIVE_FRAME_TRANSPORT_SOAK" &&
grep -q 'PMLE_DPB2_PROGRESSIVE|PASS' "$MLE_LIVE_FRAME_TRANSPORT_SOAK" &&
grep -q 'progressive=1' "$MLE_LIVE_FRAME_TRANSPORT_SOAK" &&
grep -q 'batchSoakLastTic' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'soakAfter=sample.p_last_tic' "$MLE_LIVE_FRAME_E2E" &&
  grep -q 'temporary_lob_growth=0' "$MLE_LIVE_FRAME_TRANSPORT_SOAK" ||
  fail 'progressive DPB2 temporary-LOB soak runner is not fail-closed'
[ -x "$MLE_LIVE_FRAME_TWO_POV" ] &&
[ -x "$MLE_LIVE_FRAME_TWO_POV_EVALUATOR" ] &&
[ -x "$MLE_LIVE_FRAME_ARTIFACT_MARKER" ] &&
test "$(node "$MLE_LIVE_FRAME_TWO_POV_EVALUATOR" --self-test)" = \
  'PMLE_OCI_TWO_POV_EVALUATOR_SELFTEST|PASS|mutations=10' &&
test "$(node "$MLE_LIVE_FRAME_ARTIFACT_MARKER" --self-test)" = \
  'PMLE_LIVE_FRAME_ARTIFACT_MARKER_SELFTEST|PASS|mutations=4' &&
grep -q 'DOOMDB_REQUIRE_DATABASE_PIXELS=1' "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'DOOMDB_MULTIPLAYER_FRAMES=300' "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'live-frame authority candidate is not promoted' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'from doom_mle_live_frame_source where artifact_id=1' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'PMLE_OCI_TWO_POV_ARTIFACT|authority_sha256=' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'verify-live-frame-artifact-marker[.]mjs' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'query_deployed_artifact BEFORE' "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'query_deployed_artifact AFTER' "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'PMLE_OCI_TWO_POV_ARTIFACT_ATTEST|phase=%s' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'minimum_fps=%s|renderer=DATABASE_PIXELS' \
  "$MLE_LIVE_FRAME_TWO_POV" &&
grep -q 'samples_sha256=%s' "$MLE_LIVE_FRAME_TWO_POV" &&
grep -Fq 'minimumPerformanceFps===20||minimumPerformanceFps===30' \
  "$MULTIPLAYER_CLIENT" &&
grep -Fq 'p99<=2*frameBudget&&paintMax<=3*frameBudget' \
  "$MULTIPLAYER_CLIENT" &&
grep -Fq 'minimumFps===20||minimumFps===30' \
  "$MLE_LIVE_FRAME_TWO_POV_EVALUATOR" &&
grep -q "row.source==='database-framebuffer'" "$MULTIPLAYER_CLIENT" &&
grep -q 'repeated a measured framebuffer' "$MULTIPLAYER_CLIENT" &&
grep -q 'RAW_TWO_POV_BROWSER_SAMPLES' "$MULTIPLAYER_CLIENT" &&
grep -q 'DOOMDB_REQUIRE_DATABASE_PIXELS=1' "$MULTIPLAYER_PERFORMANCE" ||
  fail 'two-POV database-pixel 20/30 FPS acceptance is absent or weakened'
grep -q 'refusing to overwrite live-frame ring-wrap evidence' \
  "$MLE_LIVE_FRAME_RING_WRAP" &&
grep -q 'DOOMDB_LIVE_FRAME_RING_WRAP=YES' "$MLE_LIVE_FRAME_RING_WRAP" &&
grep -q 'ring_wrap=RESET_GAP' "$MLE_LIVE_FRAME_RING_WRAP" &&
grep -q 'PMLE_LIVE_FRAME_RING_WRAP_EVIDENCE|PASS' \
  "$MLE_LIVE_FRAME_RING_WRAP" ||
  fail 'live-frame bounded-ring overrun evidence runner is not fail-closed'
grep -q 'restoreCheckpointWarm' "$TEAVM_SIM_SOURCE" ||
  fail 'warm checkpoint restore export missing'
grep -q 'warm checkpoint origin does not match retained engine' "$TEAVM_SIM_SOURCE" ||
  fail 'warm checkpoint restore origin fence missing'
grep -q 'create table doom_worker_stop_intent' "$MLE_WORKER_LIFECYCLE_SCHEMA" ||
  fail 'durable worker stop intent schema missing'
grep -q 'procedure reconcile_warm_slots' "$MLE_WORKER_LIFECYCLE" ||
  fail 'retained worker janitor missing'
grep -q "where slot_status='RUNNING' and assigned_match is not null" \
  "$MLE_WORKER_LIFECYCLE" &&
grep -q "failure_detail='janitor: assigned scheduler/session absent'" \
  "$MLE_WORKER_LIFECYCLE" &&
grep -q "last_error='janitor: stale assigned scheduler/session absent'" \
  "$MLE_WORKER_LIFECYCLE" ||
  fail 'dead assigned retained-worker reconciliation is absent or weakened'
grep -q "where slot_status in('WARMING','READY') and assigned_match is null" \
  "$MLE_WORKER_LIFECYCLE" ||
  fail 'unassigned retained-worker reconciliation fence changed'
grep -q "slot_status='CLAIMED'" "$MLE_WARM_LIFECYCLE_TEST" &&
grep -q 'scenario=dead_assigned_reconciled' "$MLE_WARM_LIFECYCLE_TEST" &&
grep -q 'scenario=live_assigned_noop' "$MLE_WARM_LIFECYCLE_TEST" ||
  fail 'assigned-worker janitor race coverage is absent'
grep -q 'function lifecycleCleanupAudit(match)' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'lifecycle_cleanup=PASS' "$MLE_LIVE_FRAME_E2E" ||
  fail 'database-pixel recovery does not gate retained-slot cleanup'
grep -q 'function assignedSlotAudit(match)' "$MLE_LIVE_FRAME_E2E" &&
grep -q 'DOOMDB_LIVE_FRAME_EXPECTED_SLOT' "$MLE_LIVE_FRAME_E2E" &&
[ -x "$MLE_LIVE_FRAME_CROSS_SLOT" ] &&
grep -q 'DOOMDB_LIVE_FRAME_EXPECTED_SLOT=1' "$MLE_LIVE_FRAME_CROSS_SLOT" &&
grep -q 'DOOMDB_LIVE_FRAME_EXPECTED_SLOT=2' "$MLE_LIVE_FRAME_CROSS_SLOT" &&
grep -q 'PMLE_LIVE_FRAME_CROSS_SLOT|PASS' "$MLE_LIVE_FRAME_CROSS_SLOT" &&
grep -q 'full_world_seed=1|pool_restored=1' "$MLE_LIVE_FRAME_CROSS_SLOT" &&
grep -q "slot_status='READY' and assigned_match is null" \
  "$MLE_LIVE_FRAME_CROSS_SLOT" ||
  fail 'retained live-frame cross-slot equality gate is absent or weakened'
grep -Fq 'set linesize 32767 trimspool on' "$MLE_LIVE_FRAME_DIFFERENTIALS" &&
grep -Fq 'PMLE_LIVE_FRAME_DIFFERENTIAL_PREFLIGHT|PASS|' \
  "$MLE_LIVE_FRAME_DIFFERENTIALS" &&
grep -Fq 'PMLE_LIVE_FRAME_AUTHORITY_DIFFERENTIALS|PASS|' \
  "$MLE_LIVE_FRAME_DIFFERENTIALS" ||
  fail 'live-frame differential wrapper is vulnerable to SHA marker wrapping'
grep -q 'procedure reap_abandoned_matches' "$MLE_SESSION_CLEANUP" &&
grep -q "l_now-numtodsinterval(15,'SECOND')" "$MLE_SESSION_CLEANUP" &&
grep -q 'doom_session_cleanup.reap_abandoned_matches(4)' "$DOOM_API" &&
grep -q "disconnected_at<l_now-interval '15' second" "$MLE_MATCH_WORKER" &&
grep -q "select generation into l_generation from doom_match_worker_control" \
  "$DOOM_API" &&
grep -q 'window.addEventListener.*pagehide.*releaseLocalMatchOnUnload' \
  "$MULTIPLAYER_CLIENT_TS" &&
grep -q 'window.addEventListener.*beforeunload.*releaseLocalMatchOnUnload' \
  "$MULTIPLAYER_CLIENT_TS" ||
  fail 'browser-death match/slot reclamation is absent or weakened'
grep -q 'expected incarnation mismatch' "$MLE_WORKER_LIFECYCLE" ||
  fail 'stop incarnation rejection fence missing'
grep -q 'forced after bounded honor timeout' "$MLE_WORKER_LIFECYCLE" ||
  fail 'bounded force-stop reset missing'
if grep -Rni --include='*.sql' --include='*.sh' --include='*.mjs' \
  --exclude='083_worker_lifecycle.sql' --exclude='verify-pmle-source.sh' \
  'dbms_scheduler[.]stop_job' "$ROOT/sql" "$ROOT/probes" "$ROOT/scripts" "$ROOT/tests"; then
  fail 'direct DBMS_SCHEDULER.STOP_JOB exists outside lifecycle gateway'
fi
grep -q 'publish_initial(p_match,l_generation,p_warm)' "$MLE_MATCH_WORKER" || fail 'RUN_MATCH warm/cold MLE initialization missing'
grep -q 'reconstruct_existing(p_match,l_generation' "$MLE_MATCH_WORKER" || fail 'RUN_MATCH MLE recovery missing'
grep -q 'doom_mle_match_runtime.step_game' "$MLE_MATCH_WORKER" || fail 'MLE worker step missing'
grep -q 'doom_mle_transition_transport.publish' "$MLE_MATCH_WORKER" || fail 'MLE worker DMD1 publication missing'
grep -q 'doom_mle_match_runtime.save_checkpoint(' "$MLE_MATCH_WORKER" &&
grep -q 'l_state,l_checkpoint_sha,l_checkpoint_bytes,l_checkpoint' \
  "$MLE_MATCH_WORKER" &&
grep -q 'tic<p_tic-c_checkpoint_max_tics\*2' "$MLE_MATCH_WORKER" ||
  fail 'MLE worker temporary checkpoint publication or three-checkpoint retention missing'
if grep -q 'doom_mle_match_runtime.save_checkpoint_into' "$MLE_MATCH_WORKER"; then
  fail 'MLE worker regained the measured-slow direct SecureFile checkpoint path'
fi
grep -q "checkpoint_status in('IDLE','QUEUED','PROCESSING','FAILED')" \
  "$MLE_ASYNC_CHECKPOINT_SCHEMA" &&
grep -q "standby_status='READY' and checkpoint_status='IDLE'" \
  "$MLE_MATCH_WORKER" &&
grep -q "checkpoint_status in('QUEUED','PROCESSING')" "$MLE_MATCH_WORKER" &&
grep -q 'procedure build_standby_checkpoint' "$MLE_MATCH_WORKER" &&
grep -q 'standby checkpoint replay mismatch tic=' "$MLE_MATCH_WORKER" &&
grep -Fq "and s.checkpoint_status<>'FAILED'" "$MLE_MATCH_WORKER" &&
grep -Fq 'Continuing to advertise that' "$MLE_MATCH_WORKER" &&
grep -Fq 'context. Escape to RUN_WARM_SLOT' "$MLE_MATCH_WORKER" &&
grep -q 'c_standby_checkpoint_replay_batch constant pls_integer:=1' \
  "$MLE_MATCH_WORKER" &&
grep -q 'dbms_session.sleep(c_standby_checkpoint_replay_yield)' \
  "$MLE_MATCH_WORKER" &&
grep -q "l_checkpoint_diagnostic=0" "$MLE_MATCH_WORKER" &&
grep -q "checkpoint_status='PROCESSING'" "$MLE_MATCH_WORKER" ||
  fail 'periodic DMC1 work is not fenced onto the retained standby'
grep -q 'save_elapsed_ms number(12,3) default 0 not null' \
  "$MULTIPLAYER_SCHEMA" &&
grep -q 'publish_elapsed_ms number(12,3) default 0 not null' \
  "$MULTIPLAYER_SCHEMA" &&
grep -q 'checkpoint timing publication fence' "$MLE_MATCH_WORKER" ||
  fail 'every-checkpoint save/publication timing is not durably fenced'
grep -q 'l_checkpoint_save_ms<=0 or l_checkpoint_publish_ms<0' \
  "$MLE_MATCH_WORKER_TEST" ||
  fail 'worker cutover gate does not exercise durable checkpoint timings'
grep -q 'c_checkpoint_min_tics constant pls_integer:=497' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint minimum opportunity missing'
grep -q 'c_checkpoint_max_tics constant pls_integer:=512' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint recovery hard bound missing'
grep -q 'c_checkpoint_probe_tics constant pls_integer:=16' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint opportunity cadence missing'
grep -q "l_memory_status,'awakeMonsters'" "$MLE_MATCH_WORKER" ||
  fail 'MLE low-awake checkpoint placement missing'
grep -q 'c_checkpoint_low_awake constant pls_integer:=16' "$MLE_MATCH_WORKER" ||
  fail 'MLE low-awake threshold missing'
grep -q 'c_checkpoint_recovery_diagnostic_tic constant pls_integer:=0' \
  "$MLE_MATCH_WORKER" &&
grep -q "dbms_application_info.set_action('RECOVERY_DISTANCE_WINDOW')" \
  "$MLE_MATCH_WORKER" &&
grep -q 'p_tic=c_checkpoint_recovery_diagnostic_tic' "$MLE_MATCH_WORKER" ||
  fail 'maximum-distance recovery pause is absent or live in production'
grep -q 'Test scaffold only: CHECKPOINT_TEST_HOOK may force a tic-64 checkpoint' "$MLE_MATCH_WORKER" ||
  fail 'tic-64 checkpoint scaffold is not fenced from production cadence'
grep -q 'checkpoint_test_hook number(1) default 0 not null' \
  "$ROOT/sql/schema/048_multiplayer_worker.sql" ||
  fail 'checkpoint liveness test hook is not separately fenced'
grep -q 'create table doom_match_checkpoint_probe' \
  "$ROOT/sql/schema/048_multiplayer_worker.sql" ||
  fail 'density-stratified checkpoint probe evidence table missing'
grep -q "'DEFER_HIGH'" "$MLE_MATCH_WORKER" ||
  fail 'high-awake checkpoint deferral evidence missing'
grep -q 'p_checkpoint_test_hook=1 and p_tic=64' "$MLE_MATCH_WORKER" ||
  fail 'tic-64 scaffold is not isolated from route diagnostics'
grep -q 'route_diagnostics,checkpoint_test_hook' "$MLE_MATCH_WORKER" ||
  fail 'retained worker does not refresh diagnostic controls at runtime'
grep -q 'c_checkpoint_tic constant pls_integer:=256' "$RETAINED_WORKER_TEST" ||
  fail 'retained-worker lifecycle test does not reach the checkpoint hard bound'
grep -q 'checkpoint_save_ms is not null' "$WAN_SOAK" ||
  fail 'checkpoint liveness diagnostic is pinned to an obsolete fixed tic'
grep -q 'checkpointAttemptTic=frontier+1' "$WAN_SOAK" ||
  fail 'killed-checkpoint diagnostic does not preserve the attempted tic'
grep -q 'DOOMDB_DOUBLE_RECOVERY_DIAGNOSTIC' "$WAN_SOAK" ||
  fail 'concurrent double-recovery diagnostic missing'
grep -q 'PMLE_DOUBLE_RECOVERY|PASS' "$WAN_SOAK" ||
  fail 'concurrent double-recovery terminal marker missing'
grep -q "assert.equal(Number(final\\[4\\]),1" "$WAN_SOAK" ||
  fail 'double-recovery gate does not require exactly one tier-2 assignment'
grep -q 'DOOMDB_HIGH_AWAKE_RECOVERY_DIAGNOSTIC' "$WAN_SOAK" ||
  fail 'density-stratified maximum-distance recovery diagnostic missing'
grep -q 'DOOMDB_HIGH_AWAKE_CHECKPOINT_SAVE_DIAGNOSTIC' "$WAN_SOAK" ||
  fail 'high-awake checkpoint SAVE diagnostic missing'
grep -q 'PMLE_HIGH_AWAKE_RECOVERY_STAGES|PASS' "$WAN_SOAK" ||
  fail 'maximum-distance recovery stage decomposition missing'
grep -q 'DOOMDB_CHECKPOINT_CADENCE_OBSERVATION' "$WAN_SOAK" ||
  fail 'paced production checkpoint cadence observation missing'
grep -q 'PMLE_CHECKPOINT_CADENCE_OBSERVATION|PASS' "$WAN_SOAK" ||
  fail 'paced checkpoint cadence observation terminal marker missing'
grep -q "assert.equal(cadence.testHook,0" "$WAN_SOAK" ||
  fail 'paced cadence observation is contaminated by the test hook'
grep -q 'DOOMDB_HIGH_AWAKE_RECOVERY_GATE' "$WAN_SOAK" ||
  fail 'density-stratified maximum-distance recovery acceptance mode missing'
grep -q "highAwakeRecoveryGate?recoveryVerdict:'DIAGNOSTIC_NOT_GATE'" "$WAN_SOAK" ||
  fail 'high-awake recovery measurement is not honestly classified'
grep -q 'kill window: 497–511 tics' "$TEAVM_CADENCE_DECISION" &&
grep -q 'browser/ORDS-observed recovery: 22,377 ms' \
  "$TEAVM_CADENCE_DECISION" &&
grep -q 'checked-in value is zero' "$TEAVM_CADENCE_DECISION" ||
  fail 'OCI checkpoint cadence decision is absent or incomplete'
grep -q 'PMLE_HIGH_AWAKE_GENERATION_ACTIVE' "$WAN_SOAK" ||
  fail 'high-awake feed is not fenced to the activated generation'
grep -Fq 'new RegExp(`^PMLE_HIGH_AWAKE_PRELOAD\\|' "$WAN_SOAK" ||
  fail 'high-awake preload extractor is not start-anchored'
grep -Fq 'prepared.changes.length*2}[ \\t]*$`' "$WAN_SOAK" ||
  fail 'high-awake preload extractor is not end-anchored'
grep -Fq 'new RegExp(`^PMLE_HIGH_AWAKE_FEED_ACTIVE\\|' "$WAN_SOAK" ||
  fail 'high-awake active-feed extractor is not start-anchored'
grep -Fq 'changes.length*2}[ \\t]*$`' "$WAN_SOAK" ||
  fail 'high-awake active-feed extractor is not end-anchored'
grep -q "DOOMDB_HIGH_AWAKE_RECOVERY_MAX_TICS" "$WAN_SOAK" &&
grep -q "highAwakeRecoveryMaxTics-16+1" "$WAN_SOAK" &&
grep -q "recoveryTarget.distance<highAwakeRecoveryMaxTics" "$WAN_SOAK" ||
  fail 'high-awake recovery is not killed at maximum scheduled distance'
grep -q "killedDistance>=highAwakeRecoveryMaxTics-16+1" "$WAN_SOAK" &&
grep -q "killedDistance<highAwakeRecoveryMaxTics" "$WAN_SOAK" ||
  fail 'high-awake recovery does not verify the durable killed distance'
grep -q "recoveryElapsedMs<=45000" "$WAN_SOAK" ||
  fail 'high-awake recovery does not reserve the production detection budget'
grep -q "maximum-distance restore/replay/publish exceeded its 45-second phase budget" \
  "$WAN_SOAK" ||
  fail 'high-awake recovery gate does not enforce the stratified SLA'
grep -q 'p_checkpoint_test_hook=2 and p_tic=256' "$MLE_MATCH_WORKER" ||
  fail 'high-awake checkpoint SAVE scaffold is missing'
grep -q 'if l_checkpoint_diagnostic=1 or l_checkpoint_due=1 then' \
  "$MLE_MATCH_WORKER" ||
  fail 'diagnostic checkpoint flag is not wired to the firing condition'
if grep -q 'l_checkpoint_diagnostic=1 and p_tic=64' "$MLE_MATCH_WORKER"; then
  fail 'obsolete tic-64-only diagnostic checkpoint firing gate remains'
fi
grep -q 'recovery_restore_ms=l_restore_ms' "$MLE_MATCH_WORKER" ||
  fail 'recovery restore/replay/publish instrumentation is missing'
grep -q "add_column('RECOVERY_RESTORE_MS','number')" \
  "$MLE_RECOVERY_TELEMETRY_SCHEMA" ||
  fail 'in-place recovery telemetry schema upgrade is missing'
grep -q 'highAwakeRecoveryDiagnostic&&highAwakeCheckpointSaveDiagnostic' \
  "$WAN_SOAK" ||
  fail 'high-awake diagnostic environment modes are not mutually exclusive'
grep -q 'pagesize 0 linesize 32767' "$WAN_SOAK" ||
  fail 'multiplayer evidence extractor is exposed to SQL*Plus line folding'
if grep -q 'c_checkpoint_tics constant pls_integer:=1024' "$MLE_MATCH_WORKER"; then
  fail 'obsolete 1024-tic checkpoint interval remains'
fi
grep -q 'procedure run_standby' "$MLE_MATCH_WORKER" || fail 'MLE warm standby entry point missing'
grep -q 'restore_checkpoint_warm' "$MLE_MATCH_WORKER" || fail 'MLE warm checkpoint promotion missing'
grep -q "if l_runtime_status='state=uninitialized' then" "$MLE_MATCH_WORKER" ||
  fail 'recycled warm slot does not repair a released MLE context'
grep -q 'prepare_origin_warm(2,0,3,1,1,l_state)' "$MLE_MATCH_WORKER" ||
  fail 'recycled warm slot is exposed without restoring its origin'
grep -q 'RECOVERY_TIER_1' "$MLE_MATCH_WORKER" ||
  fail 'match-bound standby recovery tier missing'
grep -q 'RECOVERY_TIER_2' "$MLE_MATCH_WORKER" ||
  fail 'unbound warm-slot recovery tier missing'
grep -q 'RECOVERY_TIER_3' "$MLE_MATCH_WORKER" ||
  fail 'cold recovery tier missing'
test "$(line_of 'RECOVERY_TIER_1' "$MLE_MATCH_WORKER")" -lt \
  "$(line_of 'RECOVERY_TIER_2' "$MLE_MATCH_WORKER")" ||
  fail 'recovery preference does not prioritize match-bound standby'
test "$(line_of 'RECOVERY_TIER_2' "$MLE_MATCH_WORKER")" -lt \
  "$(line_of 'RECOVERY_TIER_3' "$MLE_MATCH_WORKER")" ||
  fail 'recovery preference does not reserve cold init for last'
grep -q 'case when p_warm or g_warm_promotion then 1 else 0 end' "$MLE_MATCH_WORKER" ||
  fail 'unbound retained recovery does not select warm checkpoint restore'
grep -q 'c_standby_poll_seconds constant number:=5' "$MLE_MATCH_WORKER" ||
  fail 'active-match standby coarse poll missing'
perl -0777 -ne 'exit !(/dbms_session[.]sleep\(c_standby_poll_seconds\);.*?update doom_match_standby_control.*?commit;/s)' \
  "$MLE_MATCH_WORKER" ||
  fail 'passive standby heartbeat is not committed per coarse poll'
grep -q 'performs no checkpoint restore or simulation work until promotion' "$MLE_MATCH_WORKER" ||
  fail 'active-match standby passive contract missing'
grep -q "'_G'||to_char(p_generation)" "$MLE_MATCH_WORKER" || fail 'standby generation-scoped Scheduler name missing'
grep -q "p_match,'AUTHORITY',l_pool,l_job" "$MLE_MATCH_WORKER" || fail 'warm authority assignment request missing'
grep -q "p_match,'STANDBY',l_pool,l_job" "$MLE_MATCH_WORKER" || fail 'warm standby assignment request missing'
grep -q 'authority admission fence' "$MLE_MATCH_WORKER" || fail 'authority readiness transition fence missing'
grep -q 'from doom_mle_tic0_checkpoint' "$MLE_MATCH_WORKER" &&
  grep -q "authority_sha256=" "$MLE_MATCH_WORKER" &&
  grep -q 'Deployment proves every bank entry byte-identical' \
    "$MLE_MATCH_WORKER" &&
  grep -q 'doom_mle_match_runtime.save_checkpoint' "$MLE_MATCH_WORKER" ||
  fail 'warm admission does not reuse the hash-fenced tic-zero checkpoint bank'
admission_fence_line=$(grep -n "'authority admission fence'" \
  "$MLE_MATCH_WORKER" | head -1 | cut -d: -f1)
admission_commit_line=$(awk -v start="$admission_fence_line" \
  'NR>start && /commit;/{print NR;exit}' "$MLE_MATCH_WORKER")
admission_yield_line=$(awk -v start="$admission_fence_line" \
  'NR>start && /dbms_session[.]sleep[(]c_post_ready_yield_seconds[)];/{print NR;exit}' \
  "$MLE_MATCH_WORKER")
admission_standby_line=$(awk -v start="$admission_fence_line" \
  'NR>start && /arm_standby\(p_match,l_generation\);/{print NR;exit}' \
  "$MLE_MATCH_WORKER")
grep -q 'c_post_ready_yield_seconds constant number:=.1' "$MLE_MATCH_WORKER" ||
  fail 'Free-edition post-ready scheduling heuristic is not pinned'
[ "$admission_fence_line" -lt "$admission_commit_line" ] &&
  [ "$admission_commit_line" -lt "$admission_yield_line" ] &&
  [ "$admission_yield_line" -lt "$admission_standby_line" ] ||
  fail 'standby assignment can delay authority-ready admission commit'
grep -q "if l_worker_status<>'READY'" "$MLE_MATCH_WORKER" || fail 'pre-admission command fence missing'
grep -q "p_match_state:='STARTING'" "$DOOM_API" || fail 'public standby admission state missing'
grep -q 'create table doom_match_standby_control' "$ROOT/sql/schema/048_multiplayer_worker.sql" || fail 'MLE standby control schema missing'
RUN_MATCH_BODY=$(sed -n '/  procedure run_match_core(p_match in varchar2,p_warm boolean) is/,/  procedure run_match(p_match in varchar2) is/p' "$MLE_MATCH_WORKER")
printf '%s\n' "$RUN_MATCH_BODY" | grep -q 'process_step(p_match' || fail 'RUN_MATCH production step missing'
if printf '%s\n' "$RUN_MATCH_BODY" | grep -q 'doom_mocha'; then
  fail 'RUN_MATCH still reaches OJVM'
fi
grep -q 'PMLE_WORKER_CUTOVER|PASS' "$MLE_MATCH_WORKER_TEST" || fail 'MLE worker live cutover gate missing'
grep -q 'acquire DOOM_MATCH before DOOM_MATCH_MEMBER' "$DOOM_API" ||
  fail 'API canonical match-before-member lock-order invariant missing'
grep -q 'acquire DOOM_MATCH before DOOM_MATCH_MEMBER' "$MLE_MATCH_WORKER" ||
  fail 'worker canonical match-before-member lock-order invariant missing'
STARTUP_HOLD=$(sed -n '/const startupHold=dbSql(/,/PMLE_HIGH_AWAKE_STARTUP_HOLD/p' "$MULTIPLAYER_SOAK")
test "$(printf '%s\n' "$STARTUP_HOLD" | grep -n 'update doom.doom_match set' | head -1 | cut -d: -f1)" -lt \
  "$(printf '%s\n' "$STARTUP_HOLD" | grep -n 'update doom.doom_match_member set' | head -1 | cut -d: -f1)" ||
  fail 'diagnostic startup hold violates match-before-member lock order'
grep -Fq "grep -E 'ORA-[0-9]{5}'" "$ALERT_SCANNER" ||
  fail 'Oracle alert-window scanner does not fail on new ORA incidents'
grep -q "grep -v 'ORA-00000'" "$ALERT_SCANNER" ||
  fail 'Oracle alert-window scanner mistakes the success code for an incident'
for long_runner in "$TEAVM_MULTI_SOAK_RUNNER" "$TEAVM_WORKER_CUTOVER_RUNNER" \
  "$TEAVM_LEDGER_RUNNER" "$TEAVM_LIVE_MATRIX" "$HIDDEN_JIT_RUNNER" \
  "$TEAVM_DECPS_RUNNER" "$TEAVM_DECPS_GATES" "$TEAVM_DECPS_LEDGER"; do
  grep -q 'oracle-alert-window.sh' "$long_runner" ||
    fail "long diagnostic lacks Oracle alert-window gate: $long_runner"
done
grep -q 'DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH' "$TEAVM_BUILD" ||
  fail 'authority candidate patch input is unavailable'
grep -q 'authority extra patches require PMLE_AUTHORITY_CANDIDATE_BUILD=YES' \
  "$TEAVM_BUILD" ||
  fail 'authority candidate patches are not explicitly fenced'
grep -q 'authority candidate requires a stable candidate reason' \
  "$TEAVM_BUILD" ||
  fail 'authority candidate lacks a stable reason'
grep -q 'pinned authority build drift' "$TEAVM_BUILD" ||
  fail 'ordinary authority builds are not verified against versions.lock'
grep -q 'patch_set_sha256=%s' "$TEAVM_BUILD" ||
  fail 'authority candidate patch set is not content-addressed'
grep -q 'classification=%s' "$TEAVM_BUILD" ||
  fail 'authority build marker does not classify candidate output'
grep -q 'DOOMDB_TEAVM_PRESENTATION_EXTRA_PATCH' "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation candidate patch input is unavailable'
grep -q 'presentation extra patches require PMLE_PRESENTATION_CANDIDATE_BUILD=YES' \
  "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation candidate patches are not explicitly fenced'
grep -q 'presentation source-only candidate requires a stable candidate reason' \
  "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation source-only candidate lacks an explicit reason fence'
if grep -Fq 'elif [[ "$presentation_candidate" == YES' \
    "$TEAVM_PRESENTATION_BUILD"; then
  fail 'presentation candidate reason fence is conditional on patch absence'
fi
grep -q 'v.teaVM.presentation.inputBytecodeSha256' \
    "$TEAVM_PRESENTATION_BUILD" &&
  grep -q '"$actual_input_sha" != "$expected_input_sha"' \
    "$TEAVM_PRESENTATION_BUILD" &&
  grep -q 'pinned presentation build drift: input=' \
    "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation pinned build does not verify input/output provenance'
grep -q 'classification=%s' "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation build does not classify candidate output'
grep -q 'patch_set_sha256=%s' "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation candidate patch set is not content-addressed'
grep -q 'DOOMDB_TEAVM_PRESENTATION_MINIFYING' \
    "$TEAVM_PRESENTATION_BUILD" &&
  grep -q 'minifying=%s' "$TEAVM_PRESENTATION_BUILD" ||
  fail 'presentation build cannot classify debug-named reproduction output'
if rg -q 'renderPlayerFrame(DatabaseView|Length|Chunk)' \
    "$TEAVM_PRESENTATION_SOURCE"; then
  fail 'presentation-only Java exports can silently reshape the authority root'
fi
grep -q 'return SimulationEngineReachabilityProbe.renderPlayerFrame(playerSlot)' \
  "$TEAVM_PRESENTATION_SOURCE" ||
  fail 'presentation root does not reuse the pinned frame export'
grep -Fq 'byte[] pixels = (byte[]) foreground' "$TEAVM_SIM_SOURCE" ||
  fail 'browser frame export no longer preserves an immutable pixel copy'
grep -q 'project.build.outputTimestamp' \
    "$ROOT/probes/mle/teavm-engine/pom.xml" ||
  fail 'TeaVM input JAR embeds a non-reproducible wall-clock timestamp'
grep -q 'renderPlayerFrameChunk(offset, size)' "$TEAVM_PRESENTATION_NODE" ||
  fail 'presentation Node gate does not verify database frame chunks'
grep -q 'retainedDatabaseFrame.subarray(offset, offset + length)' \
    "$TEAVM_PRESENTATION_NODE" ||
  fail 'presentation Node gate does not adapt the existing frame in JavaScript'
grep -q 'browser frame mutated after later renders' "$TEAVM_PRESENTATION_NODE" ||
  fail 'presentation Node gate does not preserve browser-frame immutability'
grep -q 'database-view/chunked frame mismatch' "$TEAVM_PRESENTATION_NODE" ||
  fail 'presentation Node gate does not verify the session-bind framebuffer view'
grep -q 'has_presentation_frame' "$TEAVM_SIM_LOADER" ||
  fail 'MLE loader does not detect presentation frame exports'
grep -q 'doom_teavm_sim_frame_length' "$TEAVM_SIM_LOADER" ||
  fail 'MLE loader lacks render-once presentation call spec'
grep -q 'doom_teavm_sim_frame_chunk' "$TEAVM_SIM_LOADER" ||
  fail 'MLE loader lacks bounded presentation frame call spec'
grep -q 'PMLE_PRESENTATION_FRAME_ORACLE|PASS' "$TEAVM_PRESENTATION_FRAME_ORACLE" ||
  fail 'presentation frame Node chain oracle missing'
grep -q 'input_bytecode_sha256=%s' "$TEAVM_BUILD" ||
  fail 'authority build marker omits its input bytecode SHA'
grep -q 'mocha_bytecode_sha256=%s' "$TEAVM_BUILD" ||
  fail 'authority build marker omits its Mocha bytecode SHA'
grep -q 'PMLE_PRESENTATION_FRAME_RANK' "$TEAVM_PRESENTATION_FRAME_BENCH" &&
  grep -q "l_classification varchar2(32):='DIAGNOSTIC_NOT_GATE'" \
    "$TEAVM_PRESENTATION_FRAME_BENCH" &&
  grep -q "l_classification:='ACCEPTANCE_GATE'" \
    "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation frame direct-MLE rank marker missing'
grep -Fq 'c_frame_bytes constant pls_integer:=320*200' \
  "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation frame rank is not bound to exact 320x200 output'
grep -q "l_pipeline(l_p95_index)<=33[.]333 then 'PASS'" \
  "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation frame rank lacks the end-to-end 30 FPS p95 threshold'
grep -q 'l_total(sample_-l_warmup_count):=elapsed_ms(l_total_started)' \
  "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation frame total excludes frame assembly wall time'
grep -q 'l_pipeline(sample_-l_warmup_count):=elapsed_ms(l_pipeline_started)' \
  "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation 30 FPS gate excludes the authoritative tic'
grep -q 'p_started timestamp with time zone' \
  "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'presentation wall-clock timing can lose timezone semantics'
grep -q -- '--self-test' "$TEAVM_PRESENTATION_FRAME_EXTRACTOR" ||
  fail 'presentation frame-chain extractor lacks an offline self-test'
grep -q 'duplicate field' "$TEAVM_PRESENTATION_FRAME_EXTRACTOR" ||
  fail 'presentation frame-chain extractor accepts duplicate fields'
grep -q -- '--self-test' "$TEAVM_BUILD_SHA_EXTRACTOR" ||
  fail 'build provenance extractor lacks an offline self-test'
grep -q "kind === 'sha256'" "$TEAVM_BUILD_SHA_EXTRACTOR" &&
  grep -q "kind === 'token'" "$TEAVM_BUILD_SHA_EXTRACTOR" &&
  grep -q "kind === 'integer'" "$TEAVM_BUILD_SHA_EXTRACTOR" &&
  grep -q 'invalid build token was accepted' "$TEAVM_BUILD_SHA_EXTRACTOR" &&
  grep -q 'invalid build integer was accepted' "$TEAVM_BUILD_SHA_EXTRACTOR" &&
  grep -q 'unsupported extraction kind was accepted' \
    "$TEAVM_BUILD_SHA_EXTRACTOR" ||
  fail 'build provenance extractor does not fail closed by field kind'
grep -q -- '--self-test' "$TEAVM_STREAM_HASHER" &&
  grep -q 'invalid command stream was accepted' "$TEAVM_STREAM_HASHER" &&
  grep -q 'node "$stream_hasher" --self-test' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'stream_sha="$(node "$stream_hasher" "$stream")"' \
    "$TEAVM_DECPS_NODE_PROFILE" ||
  fail 'de-CPS profile stream hash does not validate the binary fixture shape'
grep -q -- '--self-test' "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation frame-rank comparator lacks an offline self-test'
grep -q 'PMLE_PRESENTATION_300_FRAME_GATE|PASS' \
  "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation frame comparator lacks the 300-frame acceptance marker'
grep -q 'artifact marker does not precede rank terminal' \
  "$TEAVM_PRESENTATION_FRAME_COMPARATOR" &&
  grep -q 'unbound frame gate was accepted' \
    "$TEAVM_PRESENTATION_FRAME_COMPARATOR" &&
  grep -q 'duplicate frame artifact field was accepted' \
    "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation frame decisions are not artifact-provenance bound'
grep -q 'pipeline_p95_ms <= 33[.]333' "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation frame comparator does not recompute the 30 FPS p95 verdict'
grep -q 'duplicate marker field' "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation frame comparator accepts duplicate fields'
grep -q "create mle env doom_teavm_presentation_bind_env imports" \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind wrapper lacks an import environment'
grep -q "import \\* as engine from 'doom_teavm_engine'" \
  "$TEAVM_PRESENTATION_BIND_SOURCE" ||
  fail 'presentation session-bind wrapper does not import the exact engine'
grep -q "import oracledb from 'mle-js-oracledb'" \
  "$TEAVM_PRESENTATION_BIND_SOURCE" ||
  fail 'presentation session-bind wrapper lacks the built-in SQL driver'
grep -q 'engine.renderPlayerFrame(playerSlot)' \
  "$TEAVM_PRESENTATION_BIND_SOURCE" ||
  fail 'presentation session bind does not reuse the pinned Uint8Array export'
grep -q 'export function renderPlayerFrameLength(playerSlot)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'export function renderPlayerFrameChunk(offset, length)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'retainedFrame.subarray(offset, offset + length)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'doom_teavm_bind_frame_length' \
    "$TEAVM_PRESENTATION_BIND_INSTALL" &&
  grep -q 'doom_teavm_bind_frame_chunk' \
    "$TEAVM_PRESENTATION_BIND_INSTALL" &&
  grep -q 'doom_teavm_bind_frame_length' \
    "$TEAVM_PRESENTATION_FRAME_BENCH" &&
  grep -q 'doom_teavm_bind_frame_chunk' \
    "$TEAVM_PRESENTATION_FRAME_BENCH" ||
  fail 'RAW frame evidence is not adapted through the isolated JS wrapper'
if rg -q 'doom_teavm_sim_frame_(length|chunk)' \
    "$TEAVM_PRESENTATION_FRAME_BENCH"; then
  fail 'RAW frame benchmark depends on presentation-only Java exports'
fi
grep -q 'oracledb.DB_TYPE_BLOB === undefined' \
  "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'payload.type = oracledb.DB_TYPE_BLOB' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'persistDirect(new Uint8Array(64000), -1)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q "'implicit_target_blob'" "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'val: frame' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  test "$(grep -Fc 'insert into doom_teavm_frame_sink(frame_id,payload)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -eq 1 &&
  grep -q 'function acquirePersistentLocator(frameId)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'A persistent LOB locator cannot span transactions' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'where sink_id=1' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'returning payload into :payload' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'dir: oracledb.BIND_OUT' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'type: oracledb.ORACLE_BLOB' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'Array.isArray(result.outBinds.payload)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'result.outBinds.payload.length !== 1' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -Fq 'result.outBinds.payload[0]' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'payload.open(OracleBlob.LOB_READWRITE);' \
    "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'payload.write(1, frame);' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  grep -q 'payload.close();' "$TEAVM_PRESENTATION_BIND_SOURCE" &&
  test "$(grep -Fc 'returning payload into :payload' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -eq 1 &&
  test "$(grep -Fc 'payload.open(OracleBlob.LOB_READWRITE)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -eq 1 &&
  test "$(grep -Fc 'payload.write(1, frame)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -eq 1 &&
  test "$(grep -Fc 'payload.close()' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -eq 2 &&
  grep -q 'values(-1,empty_blob());' \
    "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation wrapper lacks direct INSERT/transaction-local persistent-LOB arms'
grep -q "create function doom_teavm_bind_direct_mode return varchar2" \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation direct BLOB mode call specification missing'
grep -q "doom_teavm_bind_probe_direct<>64000" \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation direct BLOB probe does not exercise the full frame'
presentation_bind_loader_sql="$("$TEAVM_PRESENTATION_BIND_INSTALL" \
  --emit-sql \
  --engine-sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3)"
printf '%s\n' "$presentation_bind_loader_sql" |
  grep -Fq "l_direct_supported varchar2(3):='YES';" &&
  printf '%s\n' "$presentation_bind_loader_sql" |
    grep -Fq "l_direct_mode varchar2(32):='UNSUPPORTED';" &&
  printf '%s\n' "$presentation_bind_loader_sql" |
    grep -Fq "l_direct_supported:='NO';" &&
  printf '%s\n' "$presentation_bind_loader_sql" |
    grep -Fq "l_direct_mode:='UNSUPPORTED';" ||
  fail 'presentation failed direct probe cannot select the locator fallback'
if printf '%s\n' "$presentation_bind_loader_sql" |
    grep -Eq ':=(YES|NO|UNSUPPORTED);'; then
  fail 'presentation bind loader emitted an unquoted PL/SQL capability literal'
fi
bind_loader_fallback_line=$(printf '%s\n' "$presentation_bind_loader_sql" |
  grep -n -F "l_direct_mode:='UNSUPPORTED';" | tail -1 | cut -d: -f1)
bind_loader_marker_line=$(printf '%s\n' "$presentation_bind_loader_sql" |
  grep -n -F 'PMLE_PRESENTATION_BIND_INSTALL|PASS' |
  tail -1 | cut -d: -f1)
[ "$bind_loader_fallback_line" -lt "$bind_loader_marker_line" ] ||
  fail 'presentation bind fallback mode is emitted after its evidence marker'
if grep -Eq 'oracledb[.]BLOB' "$TEAVM_PRESENTATION_BIND_SOURCE"; then
  fail 'presentation session-bind wrapper uses the unsupported BLOB alias'
fi
test "$(line_of 'returning payload into :payload' \
  "$TEAVM_PRESENTATION_BIND_SOURCE")" -lt \
  "$(line_of 'result.outBinds.payload\[0\]' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" &&
  test "$(line_of 'result.outBinds.payload\[0\]' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -lt \
    "$(line_of 'payload.open(OracleBlob.LOB_READWRITE)' \
      "$TEAVM_PRESENTATION_BIND_SOURCE")" &&
  test "$(line_of 'payload.open(OracleBlob.LOB_READWRITE)' \
    "$TEAVM_PRESENTATION_BIND_SOURCE")" -lt \
    "$(line_of 'payload.write(1, frame)' "$TEAVM_PRESENTATION_BIND_SOURCE")" &&
  test "$(line_of 'payload.write(1, frame)' "$TEAVM_PRESENTATION_BIND_SOURCE")" -lt \
    "$(line_of 'payload.close()' \
      "$TEAVM_PRESENTATION_BIND_SOURCE")" ||
  fail 'presentation OracleBlob operations are not ordered fail-closed'
if grep -q 'let persistentPayload' "$TEAVM_PRESENTATION_BIND_SOURCE"; then
  fail 'presentation persistent LOB locator can illegally span transactions'
fi
grep -q 'base64_fold_width=2000' "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader lacks the safe base64 fold'
grep -q -- '--emit-sql' "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader lacks a non-mutating SQL inspection mode'
grep -Fq 'while IFS= read -r piece || [[ -n "$piece" ]]' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader can drop the final base64 piece'
grep -q 'dbms_crypto.hash(l_source,dbms_crypto.hash_sh256)' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader lacks an in-database source hash'
grep -q 'dbms_crypto.hash(l_engine,dbms_crypto.hash_sh256)' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader does not verify the imported engine'
grep -q -- '--engine-sha256=' "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader lacks an exact-engine input'
grep -q 'PMLE_PRESENTATION_BIND_STAGING|PASS' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind loader lacks a staging marker'
test "$(line_of 'PMLE_PRESENTATION_BIND_STAGING|PASS' \
  "$TEAVM_PRESENTATION_BIND_INSTALL")" -lt \
  "$(line_of 'create mle module doom_teavm_presentation_bind' \
  "$TEAVM_PRESENTATION_BIND_INSTALL")" ||
  fail 'presentation session-bind module is created before its SHA gate'
grep -q 'PMLE_PRESENTATION_BIND_INSTALL|PASS' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation session-bind import mapping is not fail-closed'
grep -q 'direct_uint8array_blob_insert,persistent_returning_oracle_blob' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" &&
  grep -q 'generated always as identity primary key' \
    "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation BLOB transports are not append-only INSERT paths'
grep -q 'PMLE_PRESENTATION_DIRECT_BIND|UNSUPPORTED' \
  "$TEAVM_PRESENTATION_BIND_INSTALL" &&
  grep -q 'direct_supported=(YES|NO)' "$TEAVM_PRESENTATION_BIND_INSTALL" &&
  grep -q 'doom_teavm_bind_probe_direct' "$TEAVM_PRESENTATION_BIND_INSTALL" ||
  fail 'presentation installer does not probe the direct BLOB capability'
test "$(grep -c 'env doom_teavm_presentation_bind_env signature' \
  "$TEAVM_PRESENTATION_BIND_INSTALL")" -eq 13 ||
  fail 'presentation bind calls do not share one retained wrapper context'
grep -q 'PMLE_FRAME_BIND_DIRECT_GATE_300' \
  "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'PMLE_FRAME_BIND_LOCATOR_DIAGNOSTIC' \
    "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'PMLE_FRAME_BIND_LOCATOR_GATE_300' \
    "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'doom_teavm_bind_persist_direct' \
    "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'doom_teavm_bind_persist_locator' \
    "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation bind rank does not preserve both capability arms'
grep -q 'PMLE_PRESENTATION_BIND_RANK' "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q "l_classification varchar2(32):='DIAGNOSTIC_NOT_GATE'" \
    "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q "l_classification:='ACCEPTANCE_GATE'" \
    "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation session-bind rank classification is missing'
grep -q "l_pipeline(l_p95_index)<=33[.]333 then 'PASS'" \
  "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation session-bind rank lacks the end-to-end 30 FPS threshold'
grep -q 'p_started timestamp with time zone' \
  "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation bind wall-clock timing can lose timezone semantics'
grep -q 'select frame_id,payload into l_sink_frame_id,l_frame' \
  "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation session-bind rank does not verify database persistence'
grep -q 'from v[$]temporary_lobs' "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'temporary_lobs_before=' "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'temporary_lobs_after=' "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'temporary_lobs_delta=' "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation persistent-locator rank lacks temporary-LOB telemetry'
grep -q 'linesize 32767' "$TEAVM_PRESENTATION_FRAME_BENCH" &&
  grep -q 'linesize 32767' "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation terminal evidence can wrap under SQL*Plus defaults'
grep -q 'gate.temporaryLobs?.delta !== 0' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" &&
  grep -q 'temporary-LOB growth was accepted' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation 300-frame gate can accept temporary-LOB growth'
grep -q 'non-monotonic or impossible timing record' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" &&
  grep -q 'non-monotonic or impossible timing record' \
    "$TEAVM_PRESENTATION_FRAME_COMPARATOR" ||
  fail 'presentation comparators can accept impossible percentile records'
grep -q "'|commit_per_frame=YES'" "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'frame persistence is not commit-qualified' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation BLOB acceptance does not require per-frame durability'
bind_persist_timing_line=$(grep -n \
  'l_persist_temporary:=elapsed_ms(l_started);' \
  "$TEAVM_PRESENTATION_BIND_BENCH" | head -1 | cut -d: -f1)
bind_commit_line=$(grep -n '^    commit;' \
  "$TEAVM_PRESENTATION_BIND_BENCH" | head -1 | cut -d: -f1)
bind_pipeline_timing_line=$(grep -n \
  'l_pipeline_temporary:=elapsed_ms(l_pipeline_started);' \
  "$TEAVM_PRESENTATION_BIND_BENCH" | head -1 | cut -d: -f1)
[ "$bind_persist_timing_line" -lt "$bind_commit_line" ] &&
  [ "$bind_commit_line" -lt "$bind_pipeline_timing_line" ] ||
  fail 'presentation pipeline timing excludes its per-frame commit'
grep -q 'delete from doom_teavm_frame_sink where sink_id<>1' \
  "$TEAVM_PRESENTATION_BIND_BENCH" &&
  grep -q 'set frame_id=-1,payload=empty_blob()' \
    "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation committed-frame rank lacks deterministic sink cleanup'
grep -q 'l_frame:=null;' "$TEAVM_PRESENTATION_BIND_BENCH" ||
  fail 'presentation verification locator can span frame transactions'
test "$(line_of 'l_pipeline_temporary:=elapsed_ms(l_pipeline_started)' \
  "$TEAVM_PRESENTATION_BIND_BENCH")" -lt \
  "$(line_of 'select frame_id,payload into l_sink_frame_id,l_frame' \
  "$TEAVM_PRESENTATION_BIND_BENCH")" ||
  fail 'presentation session-bind timing includes post-persist verification'
grep -q -- '--self-test' "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation transport comparator lacks an offline self-test'
grep -q -- '--self-test' "$TEAVM_PRESENTATION_BIND_CAPABILITY" &&
  grep -q 'duplicate presentation bind capability field' \
    "$TEAVM_PRESENTATION_BIND_CAPABILITY" &&
  grep -q 'bind_capability_extractor.*--self-test' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation bind capability extraction lacks an adversarial self-test'
grep -q 'PMLE_PRESENTATION_BIND_300_FRAME_GATE|PASS' \
  "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation session-bind comparator lacks a 300-frame gate'
grep -q 'transport A/B artifact .* mismatch' \
  "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" &&
  grep -q 'unbound transport gate was accepted' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" &&
  grep -q 'duplicate transport artifact field was accepted' \
    "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation transport decisions are not artifact-provenance bound'
grep -q 'pipelineP95 <= 33[.]333' \
  "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation transport comparator does not recompute the p95 verdict'
grep -q 'duplicate marker field' "$TEAVM_PRESENTATION_TRANSPORT_COMPARATOR" ||
  fail 'presentation transport comparator accepts duplicate fields'
grep -q 'doom_teavm_presentation_bind' "$TEAVM_SIM_LOADER" ||
  fail 'simulation replacement does not drop its presentation import dependent'
grep -q 'doom_teavm_presentation_bind' "$TEAVM_PRESENTATION_BIND_CLEANUP" ||
  fail 'presentation session-bind cleanup is incomplete'
grep -q 'doom_teavm_bind_probe_direct' \
  "$TEAVM_PRESENTATION_BIND_CLEANUP" &&
  grep -q 'doom_teavm_bind_direct_mode' \
    "$TEAVM_PRESENTATION_BIND_CLEANUP" &&
  grep -q 'doom_teavm_bind_persist_direct' \
    "$TEAVM_PRESENTATION_BIND_CLEANUP" &&
  grep -q 'doom_teavm_bind_persist_locator' \
    "$TEAVM_PRESENTATION_BIND_CLEANUP" ||
  fail 'presentation cleanup omits a BLOB capability arm'
for cleanup_source in "$TEAVM_PRESENTATION_BIND_CLEANUP" \
    "$TEAVM_SIM_CLEANUP" "$TEAVM_SIM_LOADER"; do
  for call_spec in doom_teavm_bind_probe_direct doom_teavm_bind_direct_mode \
      doom_teavm_bind_persist_direct doom_teavm_bind_persist_locator; do
    grep -q "$call_spec" "$cleanup_source" ||
      fail "presentation dependency cleanup omits $call_spec"
    test "$(line_of "$call_spec" "$cleanup_source")" -lt \
      "$(line_of 'drop mle module doom_teavm_presentation_bind' \
        "$cleanup_source")" ||
      fail "presentation dependency cleanup drops module before $call_spec"
  done
done
grep -q 'mle_chain.*node_chain' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank does not compare Node and MLE frame chains'
grep -q 'pinned_node_chain.*candidate_node_chain' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank is not pixel-bound to the pinned presentation'
grep -q 'PMLE_TEAVM_STAGING_GATE|PASS|source_bytes=.*source_sha256=' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank does not preserve database staging evidence'
grep -q 'load-mle-module.sh.*--production' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank does not restore the pinned authority'
grep -q 'oracle-alert-window.sh' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank lacks an Oracle alert window'
grep -q 'safe_to_start_pool=1' "$TEAVM_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'production_restore_or_alert_unproven' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank can restore capacity without environment proof'
presentation_restore_line=$(grep -n 'load-mle-module.sh.*--production' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" | head -1 | cut -d: -f1)
presentation_alert_line=$(grep -n '"$alert_state" PRESENTATION_DECPS_RANK' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" | head -1 | cut -d: -f1)
presentation_pool_line=$(grep -n 'doom_match_worker.start_warm_pool' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" | head -1 | cut -d: -f1)
[ "$presentation_restore_line" -lt "$presentation_alert_line" ] &&
  [ "$presentation_alert_line" -lt "$presentation_pool_line" ] ||
  fail 'presentation de-CPS capacity-last ordering drifted'
grep -q 'PMLE_FRAME_GATE_300' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation de-CPS rank cannot escalate to the 300-frame gate'
test "$(grep -c \
  'PMLE_PRESENTATION_DECPS_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER")" -ge 2 &&
  test "$(grep -c \
    'PMLE_PRESENTATION_BIND_ARTIFACT|sha256=%s|bytes=%s|classification=UNPROMOTED_CANDIDATE' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER")" -ge 2 ||
  fail 'presentation diagnostic and 300-frame logs are not artifact bound'
grep -q 'PMLE_FRAME_BIND_DIRECT_GATE_300' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'PMLE_FRAME_BIND_LOCATOR_GATE_300' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation transports cannot escalate to their 300-frame gates'
grep -q 'candidate_bind_chain.*candidate_node_chain' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation session-bind frames are not pixel-bound to Node'
grep -q '! -e "$candidate_build_evidence"' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation candidate build evidence can be overwritten'
grep -q '! -e "$baseline_build_evidence"' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation baseline build evidence can be overwritten'
grep -q 'bind_source_sha256=%s' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation terminal marker omits the wrapper provenance'
grep -q 'PMLE_PRESENTATION_AUTHORITY_ISOLATION|PASS' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation source changes are not isolated from authority bytes'
grep -q 'PMLE_AUTHORITY_CANDIDATE_BUILD=YES' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation authority-isolation rebuild is not candidate-classified'
grep -q 'presentation-only adapter changes altered the de-CPS authority artifact' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation authority-isolation gate is not fail-closed'
grep -q 'authority_isolation_evidence=%s' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation terminal marker omits authority-isolation evidence'
grep -q '"$build_sha_extractor" --self-test' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation runner does not dry-run its build provenance extractor'
grep -q 'candidate_input_sha.*authority_input_sha' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation candidate is not bound to the authority input bytecode'
grep -q 'baseline_input_sha.*authority_input_sha' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation baseline is not bound to the authority input bytecode'
grep -q 'shared_input_bytecode_sha256=%s' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation terminal marker omits shared input bytecode provenance'
grep -q 'bind_install_evidence=%s' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation terminal marker omits database loader evidence'
grep -q 'PMLE_PRESENTATION_TEMP_LOB_GRANT|PASS' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" &&
grep -q 'temporary_lob_grant_evidence=%s' \
    "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation rank does not prove temporary-LOB telemetry access'
node "$TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR" --self-test >/dev/null
grep -Eq 'normalizeDbOutput|oneDbRecord' \
  "$TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR" ||
  fail 'OCI presentation evaluator bypasses the shared DB-output parser'
grep -q 'candidate="${PMLE_OCI_PRESENTATION_CANDIDATE:-$evidence/presentation-candidate-118c37717b36.js}"' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'candidate_sha="$(shasum -a 256 "$candidate"' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q '\[\[ "$candidate_sha" =~ \^\[0-9a-f\]{64}\$' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'PMLE_OCI_PRESENTATION_EVIDENCE_TAG' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'require-db-record.mjs' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q '"$record_parser" --self-test' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q '"$oracle100" "$rank100" 100 "$candidate_sha"' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'OCI_PRESENTATION_LOCATOR_100' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'OCI_PRESENTATION_LOCATOR_300' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" ||
  fail 'OCI de-CPS presentation rank is not candidate-bound and staged'
grep -q 'PMLE_OCI_PRESENTATION_ROLLBACK_CONTRACT|PASS' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'alter package doom_mle_match_runtime compile body' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'PMLE_OCI_PRESENTATION_ROLLBACK_COMPILE|PASS|status=VALID' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'artifact-metadata.sql' "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'doom_match_worker.start_warm_pool' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" ||
  fail 'OCI presentation diagnostic lacks verified capacity-last rollback'
grep -q 'emit-command-stream-sql.mjs.*"$fixture"' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q 'PMLE_OCI_COMMAND_STREAM|PASS|stream=live-dm-2026-07-23|tics=5250|bytes=173250|sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085' \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" &&
  grep -q "drop table doom_mle_perf_vector purge" \
    "$TEAVM_OCI_PRESENTATION_DECPS_RUNNER" ||
  fail 'OCI presentation diagnostic does not stage, bind, and clean its command stream'
grep -q 'persistent_returning_oracle_blob' \
    "$TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR" &&
  grep -q 'temporary_lobs_delta' "$TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR" &&
  grep -q 'p95 <= 33.333' "$TEAVM_OCI_PRESENTATION_DECPS_EVALUATOR" ||
  fail 'OCI presentation locator verdict is not independently recomputed'
grep -q 'bind_install_pattern=' "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation bind terminal extractor lacks an offline dry-run'
test "$(line_of 'bind_install_pattern=' "$TEAVM_PRESENTATION_DECPS_RUNNER")" -lt \
  "$(line_of '"$bind_installer" "--engine-sha256=' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER")" ||
  fail 'presentation bind extractor dry-run occurs after database execution'
grep -q '"--engine-sha256=$candidate_sha"' \
  "$TEAVM_PRESENTATION_DECPS_RUNNER" ||
  fail 'presentation session-bind wrapper is not bound to candidate bytes'
grep -q 'Thread.sleep' "$TEAVM_DECPS_PATCH" ||
  fail 'de-CPS patch no longer removes the blocking wait'
grep -q 'candidate SHA mismatch' "$TEAVM_DECPS_RUNNER" ||
  fail 'de-CPS MLE runner lacks content-addressed candidate fence'
grep -q 'load-mle-module.sh.*--production' "$TEAVM_DECPS_RUNNER" ||
  fail 'de-CPS MLE runner does not restore the pinned production module'
grep -q 'default-async' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'default-async-pair' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'hidden-jit-heap' "$TEAVM_DECPS_RUNNER" &&
  grep -q '"_mle_max_heap_size"=1500' "$TEAVM_DECPS_RUNNER" ||
  fail 'de-CPS hidden-JIT closeout cells are not session-scoped'
grep -q 'const landing = windows.some' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'normalizeDbOutput' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'const inert = windows.every' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  ! grep -q 'authority_sha256=2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'clock_exclusions=' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -Fq 'samples.length * .005' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'window.improvement >= 20 && window.monotonicImprovement >= 20' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'phase=default-async-pair' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'requires exactly two full expected-stream ticker terminals' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'ticker terminals are out of order' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'adversarial self-test was not rejected' \
    "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q -- '--self-test' "$TEAVM_DECPS_ASYNC_JIT_COMPARE" &&
  grep -q 'PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS' "$TEAVM_DECPS_RUNNER" &&
  grep -Fq '[r]un-decps-ledger' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'printf 3600' "$TEAVM_DECPS_RUNNER" ||
  fail 'de-CPS async JIT pair lacks its matched-window/60-minute contract'
grep -q 'default-async-plateau' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'PMLE_ASYNC_PLATEAU_PASSES' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'async plateau pass count must be between 4 and 6' \
    "$TEAVM_DECPS_RUNNER" &&
  grep -q 'printf 7200' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'PMLE_DECPS_ASYNC_JIT_HOST_CPU' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'compiler_cpu_ticks=' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'compare-decps-async-plateau.mjs' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'warmSpread <= 10' "$TEAVM_DECPS_ASYNC_PLATEAU_COMPARE" &&
  grep -q 'deopt_attribution=NO_DIRECT_SURFACE' \
    "$TEAVM_DECPS_ASYNC_PLATEAU_COMPARE" &&
  grep -q 'markers are out of order' "$TEAVM_DECPS_ASYNC_PLATEAU_COMPARE" ||
  fail 'de-CPS async plateau lacks its 4-6 pass/CPU/clock attribution contract'
grep -q 'safe_to_start_pool=1' "$TEAVM_DECPS_RUNNER" &&
  grep -q 'cleanup_restore_or_alert_unproven' "$TEAVM_DECPS_RUNNER" &&
  grep -q '"$alert_state" DECPS_RANK' "$TEAVM_DECPS_RUNNER" ||
  fail 'de-CPS rank can restore capacity before cleanup/module/alert proof'
decps_rank_alert_line=$(grep -n '"$alert_state" DECPS_RANK' \
  "$TEAVM_DECPS_RUNNER" | head -1 | cut -d: -f1)
decps_rank_pool_line=$(grep -n 'doom_match_worker.start_warm_pool' \
  "$TEAVM_DECPS_RUNNER" | head -1 | cut -d: -f1)
[ "$decps_rank_alert_line" -lt "$decps_rank_pool_line" ] ||
  fail 'de-CPS rank validates Oracle alerts after restoring capacity'
grep -q 'DOOMDB_TEAVM_OPTIMIZATION_LEVEL=SIMPLE' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'fresh de-CPS Node profile must precede SIMPLE JIT work' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'node-decps-peak-5ec18cbe4cff-v3' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'final-artifact-repro-2026-07-25-comparison.log' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'verdict=LANDING_SIGNAL' "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'oracle_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'validate-decps-node-profile.mjs' "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'validate-decps-node-profile.mjs' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q '"$validator" "$log" "$profile"' "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085' \
    "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'Node profile artifact/build provenance mismatch' \
    "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q '"$build_extractor" "$build_log" "$build_marker" sha256' \
    "$TEAVM_DECPS_NODE_PROFILE" &&
  grep -q 'profile start, rank, and terminal are out of order' \
    "$TEAVM_DECPS_NODE_PROFILE_VALIDATE" &&
  grep -q 'invalid Node profile evidence was accepted' \
    "$TEAVM_DECPS_NODE_PROFILE_VALIDATE" &&
  grep -q 'SIGNAL_TARGETED_NOINLINE_CENSUS_ALLOWED' \
    "$TEAVM_DECPS_SIMPLE_JIT" &&
  grep -q 'SIMPLE is restricted to the unpromotable JIT-digestibility diagnostic' \
    "$TEAVM_BUILD" ||
  fail 'SIMPLE JIT diagnostic can escape its profile/signal/noncandidate fence'
if grep -q '0007-teavm-authority-sight-pooling.patch' \
    "$TEAVM_BUILD" "$TEAVM_DECPS_NODE_PROFILE" \
    "$TEAVM_DECPS_RUNNER" "$TEAVM_DECPS_SIMPLE_JIT"; then
  fail 'unranked sight/BSP patch entered an executable build path'
fi
grep -q 'compareCanonical(stepped)' "$TEAVM_DECPS_PARITY" ||
  fail 'de-CPS Node parity does not compare every tic'
grep -q 'DOOMDB_MLE_MEMBERSHIP_SQL' "$TEAVM_DECPS_GATES" ||
  fail 'de-CPS promotion gate does not bind membership to candidate bytes'
grep -Fq 'membership source must contain exactly one strict MLE SHA binding' \
    "$TEAVM_DECPS_GATES" &&
  grep -Fq "c_mle_sha constant varchar2\\\\(64\\\\):='[0-9a-f]{64}';" \
    "$TEAVM_DECPS_GATES" &&
  grep -Fq '[0-9a-f]{64}' "$TEAVM_DECPS_GATES" ||
  fail 'de-CPS promotion membership binding is not generic and fail-closed'
if grep -q 'pinned_sha=' "$TEAVM_DECPS_GATES"; then
  fail 'de-CPS promotion gate still replaces one stale historical SHA'
fi
[ -x "$TEAVM_LIVE_FRAME_GATES" ] &&
grep -q 'PMLE_LIVE_FRAME_DIFFERENTIAL_PREFLIGHT|PASS' \
  "$TEAVM_LIVE_FRAME_GATES" &&
grep -q 'l_live_sha<>l_source_sha' "$TEAVM_LIVE_FRAME_GATES" &&
grep -q 'PMLE_LIVE_FRAME_AUTHORITY_DIFFERENTIALS|PASS' \
  "$TEAVM_LIVE_FRAME_GATES" &&
grep -q 'artifact_mutation=0' "$TEAVM_LIVE_FRAME_GATES" &&
! grep -q 'load-mle-module.sh' "$TEAVM_LIVE_FRAME_GATES" ||
  fail 'live-frame differential battery can mutate or misbind authority bytes'
grep -q 'PMLE_PROMOTION_MODES' "$TEAVM_DECPS_GATES" &&
  grep -q 'invalid or duplicate promotion mode sequence' "$TEAVM_DECPS_GATES" &&
  grep -q 'canonical|coop|membership' "$TEAVM_DECPS_GATES" ||
  fail 'de-CPS promotion battery cannot fail-closed resume independent gates'
grep -q 'PMLE_CANDIDATE_FILE' "$TEAVM_LEDGER_RUNNER" ||
  fail 'ledger runner cannot prove unpromoted candidate bytes'
grep -q 'PMLE_CANDIDATE_PAIR' "$TEAVM_LEDGER_RUNNER" ||
  fail 'candidate ledger provenance classification missing'
grep -q 'load-mle-module.sh.*--production' "$TEAVM_DECPS_LEDGER" ||
  fail 'de-CPS ledger wrapper does not restore pinned production module'
grep -q 'PMLE_DECPS_LEDGER_POSTFLIGHT:-NO' \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'run-decps-reproducible-5ec18cbe-2026-07-25.log' \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'run-decps-reproducible-5ec18cbe-2026-07-25-alert-origin.txt' \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'run-decps-reproducible-5ec18cbe-2026-07-25-postflight.log' \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -Fq "trap 'exit 130' HUP INT TERM" \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'artifact-metadata.sql' "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'SLOTS=2|READY=2|BOUND=0' "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'oracle-alert-window.sh.*end' "$TEAVM_DECPS_LEDGER_POSTFLIGHT" &&
  grep -q 'PMLE_DECPS_LEDGER_POSTFLIGHT|PASS' \
    "$TEAVM_DECPS_LEDGER_POSTFLIGHT" ||
  fail 'de-CPS ledger postflight can attest before environment restoration'
grep -q 'ledgerPostflight' "$TEAVM_DECPS_READINESS" &&
  grep -q 'TERMINATED_ENVIRONMENT_VERIFIED' "$TEAVM_DECPS_READINESS" &&
  grep -q 'postflight=PASS' "$TEAVM_DECPS_READINESS" &&
  grep -q 'invalid ledger postflight was accepted' \
    "$TEAVM_DECPS_READINESS" &&
  grep -q "'ledger-postflight'" "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness can promote without the durable ledger postflight'
grep -q 'PMLE_DECPS_PROMOTION_SELFTEST|PASS' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker lacks adversarial marker self-test'
grep -q 'verify-production-java-removal-source[.]sh' \
  "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS source promotion can bypass the production Java-removal audit'
grep -q 'runtimeRetiringRefs' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker lacks runtime promotion inventory'
grep -q 'historicalRetiringRefs' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker does not preserve historical evidence'
test "$(grep -Fc "'scripts/set-decps-deployment-state.mjs'" \
    "$TEAVM_DECPS_READINESS")" -ge 2 ||
  fail 'de-CPS readiness inventory can misclassify rollback-state byte evidence'
grep -q 'runtimeRetiringArtifactRefs' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker omits content-addressed filename pins'
grep -q 'PMLE_DECPS_PROMOTION_RANK|PASS' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker omits direct-MLE rank evidence'
node "$TEAVM_DECPS_RANK_COMPARE" --self-test >/dev/null ||
  fail 'de-CPS paired rank comparator self-test failed'
node "$TEAVM_DECPS_DUAL_CLOCK_COMPARE" --self-test >/dev/null ||
  fail 'de-CPS dual-clock rank comparator self-test failed'
grep -Fq 'maximumClockFailures = Math.floor(expectedTics * 0.005)' \
    "$TEAVM_DECPS_RANK_COMPARE" &&
  grep -q 'non-positive clock samples exceed' "$TEAVM_DECPS_RANK_COMPARE" &&
  grep -q 'invalidTics' "$TEAVM_DECPS_RANK_COMPARE" &&
  grep -q 'PMLE_DECPS_RANK_CLOCK_INTEGRITY|PASS' \
    "$TEAVM_DECPS_RANK_COMPARE" &&
  grep -q 'PMLE_DECPS_RANK_COMPARISON|PASS' \
    "$TEAVM_DECPS_RANK_COMPARE" ||
  fail 'de-CPS paired rank comparator can hide or over-admit clock failures'
grep -q 'mleRankComparison' "$TEAVM_DECPS_READINESS" &&
  grep -q 'candidate_tics=192,492,957,2119,3207,3536,4062' \
    "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness does not preserve old-log comparator corroboration'
grep -q 'dualClockPredecessor' "$TEAVM_DECPS_READINESS" &&
  grep -q 'dualClockCandidate' "$TEAVM_DECPS_READINESS" &&
  grep -q 'dualClockComparison' "$TEAVM_DECPS_READINESS" &&
  grep -q 'dual-clock rank evidence does not reproduce from the raw cells' \
    "$TEAVM_DECPS_READINESS" &&
  grep -q 'clock_source=DUAL_GET_TIME_PRIMARY' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness does not regenerate and consume primary dual-clock evidence'
grep -q 'PMLE_DECPS_IDENTITY_BREAK_CLASSIFICATION|PASS|' \
    "$TEAVM_DECPS_IDENTITY_CLASSIFICATION" &&
  grep -q 'changed_class=org.teavm.classlib.java.nio.charset.impl.UTF16Decoder' \
    "$TEAVM_DECPS_IDENTITY_CLASSIFICATION" &&
  grep -q 'semantic_inheritance=REJECTED' \
    "$TEAVM_DECPS_IDENTITY_CLASSIFICATION" &&
  grep -q 'identityClassification' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS generated-code identity break is not classified or promotion-fenced'
grep -q 'dbms_utility.get_time' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'clock_delta_ms=' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'clock_suspect=' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'c_clock_disagreement_ms constant pls_integer:=30' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'dual-clock suspect cap exceeded' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'monotonic_centiseconds=' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" &&
  grep -q 'monotonic_tps=' \
    "$ROOT/probes/mle/teavm-engine/replay-command-stream-mle.sql" ||
  fail 'future de-CPS ranks lack symmetric dual-clock samples and monotonic throughput'
grep -Fq "'[r]un-decps-ledger|[b]uild-ledger-differential'" \
  "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker can race the active ledger wrapper'
grep -q 'PMLE_DECPS_PROMOTION_REPRODUCIBILITY|PASS' \
  "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker omits fresh-build provenance'
grep -q 'decps-promotion-rebuild' "$TEAVM_DECPS_REPRODUCIBILITY" ||
  fail 'de-CPS reproducibility build lacks stable candidate reason'
grep -q 'classification token' "$TEAVM_DECPS_REPRODUCIBILITY" &&
  grep -q 'candidate_reason token' "$TEAVM_DECPS_REPRODUCIBILITY" ||
  fail 'de-CPS reproducibility token fields still use SHA validation'
grep -q 'cmp -s "$candidate" "$rebuilt"' "$TEAVM_DECPS_REPRODUCIBILITY" ||
  fail 'de-CPS reproducibility build does not require byte identity'
grep -q 'PMLE_REPRODUCIBILITY_ATTEST_EXISTING' \
    "$TEAVM_DECPS_REPRODUCIBILITY" &&
  grep -q 'terminal marker already exists' "$TEAVM_DECPS_REPRODUCIBILITY" &&
  grep -q 'PMLE_DECPS_REPRODUCIBILITY_VERIFIER_RECOVERY|ATTEST_EXISTING' \
    "$TEAVM_DECPS_REPRODUCIBILITY" ||
  fail 'de-CPS reproducibility verifier recovery can overwrite or bypass evidence'
grep -Fq '[r]un-decps-ledger' "$TEAVM_DECPS_REPRODUCIBILITY" ||
  fail 'de-CPS reproducibility build can contend with its promotion ledger'
grep -q 'PMLE_LEDGER_PROVENANCE|CONFIRMED|' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker lacks single-execution ledger provenance gate'
grep -q "const runtime = exactlyOne(" "$TEAVM_DECPS_READINESS" &&
  grep -q 'ledgerArtifact, pass, runtime, provenance' \
    "$TEAVM_DECPS_READINESS" &&
  grep -q 'out-of-order evidence was accepted' "$TEAVM_DECPS_READINESS" ||
  fail 'de-CPS readiness checker lacks durable ordered ledger terminals'
grep -q 'PMLE_BROWSER_REPLICA_PROFILE' "$TEAVM_BROWSER_REPLICA_PROFILE" ||
  fail 'browser confirmed-replica stage profiler missing'
grep -q -- '--disable-background-timer-throttling' "$WAN_SOAK" ||
  fail 'two-client foreground scheduling fence missing'
grep -q 'PMLE_SOAK_BROWSER_DIAG' "$WAN_SOAK" ||
  fail 'browser soak causal presentation diagnostics missing'
grep -q 'warm recovery SLA' "$MLE_MATCH_WORKER_TEST" || fail 'MLE warm recovery SLA gate missing'
grep -q 'pre_admission_command=REJECTED' "$MLE_MATCH_WORKER_TEST" || fail 'pre-admission command live gate missing'
grep -q "l_public_state<>'STARTING'" "$MLE_MATCH_WORKER_TEST" || fail 'public STARTING live gate missing'
grep -q 'environment-metadata.sql' "$TEAVM_WORKER_CUTOVER_RUNNER" || fail 'worker cutover environment metadata missing'
grep -q 'artifact-metadata.sql' "$TEAVM_WORKER_CUTOVER_RUNNER" || fail 'worker cutover artifact binding missing'
grep -q 'Oracle-resident IWAD staging mismatch' "$IWAD_LOADER" || fail 'IWAD database staging SHA gate missing'
grep -q 'Oracle-resident asset staging mismatch' "$IWAD_LOADER" || fail 'derived asset database staging SHA gate missing'
grep -q 'grant execute on sys.dbms_crypto to DOOM' "$RUNTIME_GRANTS" || fail 'fresh-install DBMS_CRYPTO grant missing'
grep -q 'grant select on sys.v_[$]temporary_lobs to DOOM' "$RUNTIME_GRANTS" ||
  fail 'fresh-install temporary-LOB telemetry grant missing'
grep -Fq 'grant select on sys.v_$rsrcpdbmetric to DOOM' "$RUNTIME_GRANTS" || fail 'resource-manager PDB cap grant missing'
grep -q 'PMLE_ENVIRONMENT|cpu_count=' "$ENVIRONMENT_SQL" || fail 'resource-manager evidence metadata missing'
grep -q 'PMLE_ARTIFACT|source_bytes=' "$ARTIFACT_SQL" || fail 'A/B artifact evidence metadata missing'
grep -q 'artifact-metadata.sql' "$TEAVM_DISPATCH_AB" || fail 'A/B artifact binding missing'
grep -q 'resmgr=' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'resource-manager slow-call attribution missing'
grep -q 'category=.*RESOURCE_MANAGER' "$TEAVM_MULTI_SOAK_RUNNER" || fail 'resource-manager wait category missing'
grep -q 'procedure poll_match_transitions' "$DOOM_API" || fail 'DMB1 public long-poll endpoint missing'
grep -q 'doom_mle_transition_transport.poll_batch' "$DOOM_API" || fail 'DMB1 public endpoint transport binding missing'
grep -q 'procedure match_checkpoint' "$DOOM_API" ||
  fail 'confirmed browser checkpoint endpoint missing'
grep -q 'match checkpoint SHA fence' "$DOOM_API" ||
  fail 'confirmed browser checkpoint database SHA fence missing'
grep -q '"version": "0.15.0"' "$VERSIONS" || fail 'TeaVM version pin missing'
grep -q '"inputBytecodeSha256": "289edf1d678f9aced34c969ed24dcc9c90b9dce38f1b15701b284a2e5384df7e"' "$VERSIONS" || fail 'TeaVM input bytecode pin missing'
grep -q '"mochaBytecodeSha256": "c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4"' "$VERSIONS" || fail 'TeaVM Mocha bytecode pin missing'
grep -q '"outputSha256": "66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873"' "$VERSIONS" || fail 'TeaVM output pin missing'
grep -q '"authoritySelection": "EXACT_SHA_SELECTED_TEA_VM_0_15_NONDETERMINISTIC_EMISSION"' \
  "$VERSIONS" &&
grep -q '"authorityReproducible": false' "$VERSIONS" ||
  fail 'exact-SHA authority selection is not explicitly classified'
grep -q '"outputSha256": "e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc"' "$VERSIONS" || fail 'TeaVM presentation output pin missing'
grep -q 'mle-js-plsql-ffi' "$HYBRID_INSTALL" || fail 'FFI comparison path missing'
grep -q 'PMLE_GATE|PASS|scope=mechanics_only|architecture=mle_command_stream' "$RUNNER" || fail 'mechanics-only architecture marker missing'
grep -q 'PMLE_COMMAND_GATE|PASS' "$REPORT" || fail 'measured hybrid report missing terminal marker'
grep -q 'PMLE_TEAVM_SIMULATION_LOAD|bytes=1158461|table_pack_bytes=180272' "$REPORT" || fail 'full-ticker stored-module evidence missing'
grep -q 'PMLE_TEAVM_TICKER|warmup=30|samples=300' "$REPORT" || fail 'real-IWAD ticker evidence missing'
grep -q 'PMLE_TEAVM_TICKER_BARE|warmup=30|samples=300|p50_ms=7.699|p95_ms=14.926' "$REPORT" || fail 'bare ticker gate evidence missing'
grep -q 'PMLE_TEAVM_DIFFERENTIAL|PASS|tics=330|fields=14' "$REPORT" || fail 'OJVM/MLE differential evidence missing'
grep -q 'zero `Math.sin`' "$TEAVM_REPORT" || fail 'runtime host-math closure evidence missing'
grep -q '1,000,196' "$TEAVM_REPORT" || fail 'deterministic sqrt property evidence missing'
grep -q 'action/collision code at 21.3%' "$TEAVM_REPORT" || fail 'Node candidate profile evidence missing'
grep -q "PMLE_DECPS_PROMOTION !== 'YES'" "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS promotion explicit apply opt-in fence missing'
grep -q 'const readinessOutput = run(' "$TEAVM_DECPS_PROMOTION" &&
  grep -Fq '[readiness],' "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS promotion readiness-before-write fence missing'
grep -q 'authorityExtraPatchSetSha256' "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS promotion patch-set provenance fence missing'
grep -q 'authorityExtraPatches' "$TEAVM_BUILD" &&
  grep -q 'pinned authority patch-set drift' "$TEAVM_BUILD" ||
  fail 'pinned authority rebuild does not apply and verify promoted patches'
grep -q '0006-teavm-authority-no-blocking-wait.patch' \
  "$ROOT/probes/mle/teavm-engine/wasm2js/build.sh" &&
  grep -q '"$spike/build.sh".*tee.*build_log' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'decps=YES' "$WASM2JS_I64_DIAGNOSTIC" ||
  fail 'wasm2js i64 diagnostic is not rebuilt from the de-CPS source set'
grep -q 'content-addressed browser authority copy failed verification' \
  "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS promotion browser artifact SHA fence missing'
grep -q 'promotion-5ec18cbe-2026-07-25.log' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'promotionEvidenceCreated = true' "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'rmSync(promotionEvidence' "$TEAVM_DECPS_PROMOTION" &&
grep -q 'PMLE_DECPS_SOURCE_PROMOTION_VERIFIERS|PASS' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'PMLE_DECPS_SOURCE_PROMOTION|PASS|bytes=' \
    "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS source promotion lacks rollback-coupled durable evidence'
promotion_evidence_line=$(grep -n \
  'writeAtomically(promotionEvidenceRelative' "$TEAVM_DECPS_PROMOTION" |
  head -1 | cut -d: -f1)
promotion_dashboard_line=$(grep -n \
  "\\['scripts/build-mle-dashboard-status.mjs'\\]" \
  "$TEAVM_DECPS_PROMOTION" | head -1 | cut -d: -f1)
[ "$promotion_evidence_line" -lt "$promotion_dashboard_line" ] ||
  fail 'de-CPS dashboard can publish a missing source-promotion evidence link'
grep -q 'PMLE_DECPS_SOURCE_PROMOTION_IN_PROGRESS' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'verifyPresentationInputTransition' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'PMLE_DECPS_INPUT_PROVENANCE_TRANSITION|PASS' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'presentation_source_sha256=' "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'simulation_source_sha256=' "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'versions.teaVM.inputBytecodeSha256 = provenance.inputBytecodeSha256' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'inputRuntimePaths' "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'retiring-input-bytecode-SHA' "$TEAVM_DECPS_READINESS" &&
  grep -q 'reproducible input-JAR configuration drifted' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'project.build.outputTimestamp' \
    "$ROOT/probes/mle/teavm-engine/pom.xml" &&
  grep -q 'source-pinned dashboard lacks exactly one completed promotion PASS' \
    "$TEAVM_DASHBOARD_STATUS" &&
  grep -q 'dashboard evidence path is missing' \
    "$ROOT/tests/verify-mle-dashboard.mjs" ||
  fail 'de-CPS dashboard/provenance source-pending transaction is not fail-closed'
grep -q 'for (const \[relativePath, original\] of originals)' \
  "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS promotion rollback fence missing'
grep -q 'existsSync(candidateBrowserArtifact)' "$TEAVM_DECPS_PROMOTION" &&
  grep -q 'writeAtomically(relativePath, original.bytes, original.mode)' \
    "$TEAVM_DECPS_PROMOTION" &&
  grep -q "flag: 'wx'" "$TEAVM_DECPS_PROMOTION" ||
  fail 'de-CPS source promotion/rollback writes are not atomic and exclusive'
grep -q 'PMLE_DECPS_DEPLOY:-NO' "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS database deployment explicit opt-in fence missing'
grep -q 'PMLE_DECPS_DEPLOY_ROLLBACK|PASS' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'DOOMDB_TIC0_AUTHORITY="$rollback"' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'install_worker_contract "$rollback_sha"' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'verify_deployed_contract' "$TEAVM_DECPS_DEPLOY" &&
  grep -q "name='DOOM_MLE_MATCH_RUNTIME' and type='PACKAGE BODY'" \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q "object_name='DOOM_MLE_MATCH_RUNTIME'" "$TEAVM_DECPS_DEPLOY" &&
  grep -q "object_type='PACKAGE BODY' and status='VALID'" \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'linesize 32767 trimspool on' "$TEAVM_DECPS_DEPLOY" &&
  ! grep -q "name='DOOM_MATCH_WORKER' and type='PACKAGE BODY'" \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_ROLLBACK_WORKER_CONTRACT' "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS deployment rollback omits module, bank, or worker contract'
grep -q 'intervention_reason=rollback_unproven' \
  "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS deployment can reopen capacity after an unproven rollback'
grep -q '^park_pool() {' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_ROLLBACK_POOL|PASS|live_slots=0' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'intervention_reason=rollback_pool_park_failed' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'rollback_permitted=0' "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS rollback can replace a module under live retained workers'
if grep -Fq '"$pool_parked" == 0' "$TEAVM_DECPS_DEPLOY"; then
  fail 'de-CPS rollback trusts stale pool bookkeeping after partial restart'
fi
grep -Fq 'elif [[ "$pool_parked" == 1 && "$capacity_hold_proven" == 1 ]]' \
    "$TEAVM_DECPS_DEPLOY" &&
  test "$(grep -c 'capacity_hold_proven=0' "$TEAVM_DECPS_DEPLOY")" -eq 2 &&
  test "$(grep -c 'pool_parked=0' "$TEAVM_DECPS_DEPLOY")" -ge 5 ||
  fail 'de-CPS unproven capacity can be relabeled held by stale shell state'
deploy_rollback_park_line=$(grep -n \
  'PMLE_DECPS_DEPLOY_ROLLBACK_POOL|PASS|live_slots=0' \
  "$TEAVM_DECPS_DEPLOY" | head -1 | cut -d: -f1)
deploy_rollback_begin_line=$(grep -n 'PMLE_DECPS_DEPLOY_ROLLBACK|BEGIN' \
  "$TEAVM_DECPS_DEPLOY" | head -1 | cut -d: -f1)
[ "$deploy_rollback_park_line" -lt "$deploy_rollback_begin_line" ] ||
  fail 'de-CPS rollback mutates the module before proving the pool parked'
grep -q 'DECPS_DEPLOY_ROLLBACK' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'alert_validation_failed=1' "$TEAVM_DECPS_DEPLOY" &&
  grep -q '"$alert_state" "$alert_label"' "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS rollback lacks a dedicated fail-closed Oracle alert window'
deploy_trap_alert_line=$(grep -n 'if \[\[ "$alert_started" == 1 \]\]; then' \
  "$TEAVM_DECPS_DEPLOY" | head -1 | cut -d: -f1)
deploy_trap_pool_line=$(grep -n \
  'if \[\[ "$pool_parked" == 1 && "$safe_to_start_pool" == 1 \]\]; then' \
  "$TEAVM_DECPS_DEPLOY" | head -1 | cut -d: -f1)
[ "$deploy_trap_alert_line" -lt "$deploy_trap_pool_line" ] ||
  fail 'de-CPS rollback can reopen capacity before alert-window validation'
grep -q 'deployment_alert_window_failed' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'dashboard_state_update_failed' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'capacity_restart_failed' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_DASHBOARD_INTERVENTION_RETRY|PASS' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_DASHBOARD_INTERVENTION_RETRY|FAIL' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_DASHBOARD_RESTART_FAILURE|PASS' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_DASHBOARD_RESTART_FAILURE|FAIL' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -Fq 'reason=([a-z0-9_]+)' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -Fq 'reason=([a-z0-9_]+)' "$TEAVM_DASHBOARD_STATUS" ||
  fail 'de-CPS intervention state does not preserve its held-capacity reason'
if grep -q '|| true' "$TEAVM_DECPS_DEPLOY"; then
  fail 'de-CPS intervention/dashboard failure can be silently discarded'
fi
grep -q "match_state in('LOBBY','ACTIVE')" "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS deployment can invalidate a starting lobby context'
grep -q 'load-tic0-checkpoint-bank.sh' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'install_worker_contract "$candidate_sha"' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'verify_deployed_contract' "$TEAVM_DECPS_DEPLOY" &&
  grep -Fq '"$candidate_sha" "$candidate_bytes" PMLE_DECPS_WORKER_CONTRACT' \
    "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS deployment does not bind module, checkpoint bank, and worker'
grep -q 'DOOMDB_TIC0_EXPECT_EQUIVALENT_AUTHORITY_SHA' \
  "$TEAVM_TIC0_LOADER" &&
  grep -q 'dbms_crypto.hash(checkpoint_blob,dbms_crypto.hash_sh256)' \
    "$TEAVM_TIC0_LOADER" &&
  grep -q 'PMLE_TIC0_BANK_EQUIVALENCE|PASS|entries=10' \
    "$TEAVM_TIC0_LOADER" &&
grep -q 'PMLE_TIC0_BANK_EQUIVALENCE|PASS|entries=10' \
    "$TEAVM_DECPS_DEPLOY" ||
  fail 'de-CPS deployment lacks full ten-entry checkpoint-bank equivalence'
grep -q 'PMLE_DECPS_DEPLOY_DATABASE|READY' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'build-mle-dashboard-status.mjs' "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'PMLE_DECPS_DEPLOY_DASHBOARD_ROLLBACK|PASS' \
    "$TEAVM_DECPS_DEPLOY" &&
  grep -q 'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING' \
    "$TEAVM_DASHBOARD_STATUS" &&
  grep -q 'INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED' \
    "$TEAVM_DASHBOARD_STATUS" &&
  grep -q 'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN' \
    "$TEAVM_DASHBOARD_STATUS" ||
  fail 'de-CPS source pin can be reported as database deployed prematurely'
grep -q 'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'duplicate argument:' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'unsupported argument:' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'cannot carry a lifecycle evidence commit' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'cannot reuse failed or held-capacity evidence' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'only the deployed-pending state may become lifecycle-qualified' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'PMLE_DECPS_DEPLOY|PASS|bytes=1081335' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q "const requiredGates = \\[" "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q "'finalSoak'" "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'lifecycle manifest must contain exactly the four required gates' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'evidence commit lacks exactly one terminal database deployment PASS' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'rollbackArtifactMarker' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'rollbackContractMarker' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'PMLE_DECPS_DEPLOY_CAPACITY.*UNPROVEN' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'finalCapacityEvidence' "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'record.interventionReason = capacity.reason' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'dashboard intervention reason does not match final capacity evidence' \
    "$TEAVM_DASHBOARD_STATUS" &&
  grep -q "'verified rollback'" "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q "'qualified deployment evidence'" "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'qualified lifecycle state requires a full evidence commit' \
    "$TEAVM_DEPLOYMENT_STATE" &&
  grep -q 'marker must occur as exactly one complete line in committed evidence' \
    "$TEAVM_DEPLOYMENT_STATE" ||
  fail 'de-CPS lifecycle qualification is not bound to committed gate evidence'
grep -q "const gateNames = \\['recovery', 'admission', 'lifecycle', 'finalSoak'\\]" \
  "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING' \
    "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'exactLineOccurrences' "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'hasPassToken' "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'evidence must bind exactly one promoted artifact tuple' \
    "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'deployment predecessor must contain exactly one terminal PASS' \
    "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q "'deployment predecessor'" "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -Fq 'assertOrdered(text, [artifactMarker, marker]' \
    "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'marker must occur exactly once' "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q "versions.teaVM.outputSha256" "$TEAVM_LIFECYCLE_MANIFEST" &&
  grep -q 'PMLE_DECPS_LIFECYCLE_MANIFEST|PASS' \
    "$TEAVM_LIFECYCLE_MANIFEST" ||
  fail 'de-CPS lifecycle manifest is not fail-closed on all four PASS gates'
grep -q 'hasPassToken(entry.marker)' "$TEAVM_DEPLOYMENT_STATE" ||
  fail 'de-CPS lifecycle qualifier can accept an embedded PASS substring'
grep -q 'evidence must bind exactly one promoted artifact tuple' \
  "$TEAVM_DEPLOYMENT_STATE" ||
  fail 'de-CPS lifecycle qualifier can accept a PASS from another artifact'
deploy_ready_line=$(grep -n 'PMLE_DECPS_DEPLOY_DATABASE|READY' \
  "$TEAVM_DECPS_DEPLOY" | tail -1 | cut -d: -f1)
deploy_dashboard_line=$(grep -n -- '--state DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING' \
  "$TEAVM_DECPS_DEPLOY" | tail -1 | cut -d: -f1)
deploy_alert_end_line=$(grep -n '"$alert_state" DECPS_DEPLOY | tee -a "$log"' \
  "$TEAVM_DECPS_DEPLOY" | tail -1 | cut -d: -f1)
deploy_pool_line=$(grep -n '^start_pool$' "$TEAVM_DECPS_DEPLOY" |
  tail -1 | cut -d: -f1)
deploy_pass_line=$(grep -n "printf 'PMLE_DECPS_DEPLOY|PASS" \
  "$TEAVM_DECPS_DEPLOY" | tail -1 | cut -d: -f1)
[ "$deploy_ready_line" -lt "$deploy_dashboard_line" ] &&
  [ "$deploy_dashboard_line" -lt "$deploy_alert_end_line" ] &&
  [ "$deploy_alert_end_line" -lt "$deploy_pool_line" ] &&
  [ "$deploy_pool_line" -lt "$deploy_pass_line" ] ||
  fail 'de-CPS database/dashboard/final deployment markers are misordered'

printf '%s\n' 'PASS PMLE-SOURCE (pure MLE, native PL/SQL, FFI, command boundary, and cleanup gates)'
