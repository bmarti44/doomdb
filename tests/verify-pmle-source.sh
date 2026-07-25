#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$ROOT/tests/verify-pmle-checkpoint-cadence.mjs"
sh "$ROOT/tests/verify-pmle-wasm2js-source.sh"
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
TEAVM_CADENCE_DECISION=$ROOT/artifacts/performance/pmle-worker-soak/checkpoint-cadence-decision-2026-07-24.md
TEAVM_BROWSER_REPLICA_PROFILE=$ROOT/probes/mle/teavm-engine/profile-browser-replica.mjs
TEAVM_WAN_RUNNER=$ROOT/probes/mle/teavm-engine/run-wan-matrix.sh
ALERT_SCANNER=$ROOT/scripts/oracle-alert-window.sh
TEAVM_LIVE_MATRIX=$ROOT/probes/mle/teavm-engine/run-live-command-matrix-mle.sh
HIDDEN_JIT_RUNNER=$ROOT/probes/mle/run-hidden-jit-matrix.sh
WASM2JS_README=$ROOT/probes/mle/teavm-engine/wasm2js/README.md
WASM2JS_PARITY=$ROOT/probes/mle/teavm-engine/wasm2js/run-node-parity.mjs
WASM2JS_I64_DIAGNOSTIC=$ROOT/probes/mle/teavm-engine/wasm2js/run-i64-lowering-diagnostics.sh
WASM2JS_SERIALIZER_WORKAROUND=$ROOT/probes/mle/teavm-engine/wasm2js/run-serializer-workaround.sh
WASM2JS_SERIALIZER_PATCH=$ROOT/probes/mle/teavm-engine/wasm2js/0003-canonical-long-high-word-workaround.patch
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
MLE_WORKER_LIFECYCLE=$ROOT/sql/sim/083_worker_lifecycle.sql
MLE_WORKER_LIFECYCLE_SCHEMA=$ROOT/sql/schema/062_mle_warm_lifecycle.sql
MLE_RECOVERY_TELEMETRY_SCHEMA=$ROOT/sql/schema/064_mle_recovery_telemetry.sql
MLE_MATCH_WORKER=$ROOT/sql/sim/084_multiplayer_worker.sql
MLE_MATCH_WORKER_TEST=$ROOT/tests/verify-mle-match-worker-cutover.sql
DOOM_API=$ROOT/sql/rest/010_doom_api.sql
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
  "$TEAVM_DECPS_ASYNC_JIT_COMPARE" "$TEAVM_DECPS_RANK_COMPARE" \
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
  "$REPORT" "$TEAVM_REPORT" "$VERSIONS" \
  "$AUTHORITY_TS" "$AUTHORITY_MIRROR_TS" "$AUTHORITY_BATCH_TS" \
  "$AUTHORITY_WAN_TS" \
  "$AUTHORITY_SQL" "$AUTHORITY_TRANSPORT" "$AUTHORITY_TRANSPORT_SCHEMA" \
  "$MLE_MATCH_RUNTIME" "$MLE_WORKER_LIFECYCLE" \
  "$MLE_WORKER_LIFECYCLE_SCHEMA" "$MLE_MATCH_WORKER" "$MLE_MATCH_WORKER_TEST" \
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
grep -q '"$wasm2js" -O0 "$wasm"' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q '"$wasm_dis" --emit-module-names' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'PMLE_WASM2JS_SERIALIZER_DISASSEMBLY|BEGIN' \
    "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'DOOMDB_WASM2JS_TICS=0' "$WASM2JS_I64_DIAGNOSTIC" ||
  fail 'wasm2js i64 O0/disassembly diagnostics are not fail-closed'
grep -q 'CALL_BOUNDARY_HIGH_WORD_LOSS' "$WASM2JS_I64_DIAGNOSTIC" &&
  grep -q 'PMLE_WASM2JS_I64_REDUCTION_CASE' "$WASM2JS_PARITY" &&
  grep -q 'canonicalFlagsHigh' "$WASM2JS_SERIALIZER_PATCH" &&
  grep -q 'DOOMDB_WASM2JS_ADAPTER_PATCH' \
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
grep -q 'transitionHoldMs, 32' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN bounded long-poll client binding missing'
grep -q 'HIDDEN_CHECKPOINT_THRESHOLD_MS = 5_000' "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab checkpoint threshold missing'
grep -q "strategy:'poll-lease-released'" "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab poll lease release missing'
grep -q "reason:'confirmed-checkpoint'" "$ROOT/client/src/multiplayer.ts" ||
  fail 'WAN hidden-tab checkpoint resync missing'
grep -q 'restoreBrowserAuthorityCheckpoint' "$ROOT/client/src/teavm-browser.ts" ||
  fail 'browser DMC1 restore binding missing'
grep -q 'PMLE_WAN_PROXY|READY' "$WAN_PROXY" || fail 'WAN proxy readiness marker missing'
grep -q 'PMLE_WAN_GATE|PASS' "$WAN_SOAK" || fail 'WAN browser acceptance marker missing'
grep -q 'neutral substitution rate' "$WAN_SOAK" || fail 'WAN neutral-substitution gate missing'
grep -q 'input/presentation p95' "$WAN_SOAK" ||
  fail 'WAN input-to-presentation gate missing'
grep -q 'never acceptable' "$WAN_SOAK" ||
  fail 'WAN long-poll hold exclusion missing'
grep -q 'presentation p99' "$WAN_SOAK" || fail 'WAN presentation-cadence gate missing'
grep -q 'PMLE_WAN_MATRIX|PASS' "$TEAVM_WAN_RUNNER" || fail 'WAN matrix terminal marker missing'
grep -q 'long_poll_enabled=1' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix long-poll enablement missing'
grep -q 'DOOMDB_WAN_HOLD_MS=500' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix bounded hold missing'
grep -q 'DOOMDB_WAN_BACKGROUND_SCENARIO=1' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix background/refocus scenario missing'
grep -q 'PMLE_WAN_TRANSPORT|long_poll=ON' "$TEAVM_WAN_RUNNER" ||
  fail 'WAN matrix cloud-shaped pool metadata missing'
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
grep -q 'dbms_alert.waitone' "$AUTHORITY_TRANSPORT" || fail 'DMB1 prompt commit alert missing'
grep -q 'doom_match_slow_call' "$ROOT/sql/schema/048_multiplayer_worker.sql" || fail 'worker slow-call schema missing'
grep -q 'record_slow_call' "$ROOT/sql/sim/084_multiplayer_worker.sql" || fail 'worker post-commit slow-call attribution missing'
grep -q 'cpu_sample_tic number(12)' "$ROOT/sql/schema/048_multiplayer_worker.sql" ||
  fail 'authority CPU telemetry schema missing'
grep -q 'procedure sample_authority_cpu' "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'authority CPU telemetry sampler missing'
grep -q 'dbms_utility.get_cpu_time' "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'authority session CPU source missing'
grep -q "set_action('MLE_CHECKPOINT')" "$ROOT/sql/sim/084_multiplayer_worker.sql" ||
  fail 'authority checkpoint liveness action missing'
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
grep -q 'doom_teavm_sim_multi_init_game' "$MLE_MATCH_RUNTIME" || fail 'MLE worker game initialization missing'
grep -q 'doom_teavm_sim_authority_step' "$MLE_MATCH_RUNTIME" || fail 'MLE worker authoritative step missing'
grep -q 'doom_teavm_sim_checkpoint_chunk' "$MLE_MATCH_RUNTIME" || fail 'MLE worker checkpoint export missing'
grep -q 'doom_teavm_sim_restore_load' "$MLE_MATCH_RUNTIME" || fail 'MLE worker checkpoint recovery missing'
grep -q 'doom_teavm_sim_restore_warm' "$MLE_MATCH_RUNTIME" ||
  fail 'fail-closed warm MLE checkpoint restore missing'
grep -q 'restoreCheckpointWarm' "$TEAVM_SIM_SOURCE" ||
  fail 'warm checkpoint restore export missing'
grep -q 'warm checkpoint origin does not match retained engine' "$TEAVM_SIM_SOURCE" ||
  fail 'warm checkpoint restore origin fence missing'
grep -q 'create table doom_worker_stop_intent' "$MLE_WORKER_LIFECYCLE_SCHEMA" ||
  fail 'durable worker stop intent schema missing'
grep -q 'procedure reconcile_warm_slots' "$MLE_WORKER_LIFECYCLE" ||
  fail 'retained worker janitor missing'
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
grep -q 'doom_mle_match_runtime.save_checkpoint' "$MLE_MATCH_WORKER" || fail 'MLE worker DMC1 checkpoint missing'
grep -q 'c_checkpoint_min_tics constant pls_integer:=113' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint minimum opportunity missing'
grep -q 'c_checkpoint_max_tics constant pls_integer:=128' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint recovery hard bound missing'
grep -q 'c_checkpoint_probe_tics constant pls_integer:=16' "$MLE_MATCH_WORKER" ||
  fail 'MLE checkpoint opportunity cadence missing'
grep -q "l_memory_status,'awakeMonsters'" "$MLE_MATCH_WORKER" ||
  fail 'MLE low-awake checkpoint placement missing'
grep -q 'c_checkpoint_low_awake constant pls_integer:=16' "$MLE_MATCH_WORKER" ||
  fail 'MLE low-awake threshold missing'
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
grep -q 'requires a durable kill distance of 112–127 tics' \
  "$TEAVM_CADENCE_DECISION" &&
  ! grep -q 'acceptance mode requires.*240–255 tics' \
    "$TEAVM_CADENCE_DECISION" ||
  fail 'checkpoint cadence decision still presents the superseded range as current'
grep -q 'PMLE_HIGH_AWAKE_GENERATION_ACTIVE' "$WAN_SOAK" ||
  fail 'high-awake feed is not fenced to the activated generation'
grep -Fq 'new RegExp(`^PMLE_HIGH_AWAKE_PRELOAD\\|' "$WAN_SOAK" ||
  fail 'high-awake preload extractor is not start-anchored'
grep -q 'prepared[.]changes[.]length[*]2}[$]' "$WAN_SOAK" ||
  fail 'high-awake preload extractor is not end-anchored'
grep -Fq 'new RegExp(`^PMLE_HIGH_AWAKE_FEED_ACTIVE\\|' "$WAN_SOAK" ||
  fail 'high-awake active-feed extractor is not start-anchored'
grep -q 'changes[.]length[*]2}[$]' "$WAN_SOAK" ||
  fail 'high-awake active-feed extractor is not end-anchored'
grep -q "recoveryTarget.distance>=112&&recoveryTarget.distance<=127" "$WAN_SOAK" ||
  fail 'high-awake recovery is not killed at maximum scheduled distance'
grep -q "killedDistance>=112&&killedDistance<=127" "$WAN_SOAK" ||
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
grep -q 'c_standby_poll_seconds constant number:=1' "$MLE_MATCH_WORKER" ||
  fail 'active-match standby coarse poll missing'
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
grep -q '"inputBytecodeSha256": "2ca1278998385efb83aba0358119f70f2e135b569b446f6b43f6afddf51ca914"' "$VERSIONS" || fail 'TeaVM input bytecode pin missing'
grep -q '"mochaBytecodeSha256": "c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4"' "$VERSIONS" || fail 'TeaVM Mocha bytecode pin missing'
grep -q '"outputSha256": "5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3"' "$VERSIONS" || fail 'TeaVM output pin missing'
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
