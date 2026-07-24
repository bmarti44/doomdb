#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$ROOT/tests/verify-pmle-checkpoint-cadence.mjs"
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
TEAVM_BROWSER_REPLICA_PROFILE=$ROOT/probes/mle/teavm-engine/profile-browser-replica.mjs
TEAVM_WAN_RUNNER=$ROOT/probes/mle/teavm-engine/run-wan-matrix.sh
ALERT_SCANNER=$ROOT/scripts/oracle-alert-window.sh
TEAVM_LIVE_MATRIX=$ROOT/probes/mle/teavm-engine/run-live-command-matrix-mle.sh
HIDDEN_JIT_RUNNER=$ROOT/probes/mle/run-hidden-jit-matrix.sh
TEAVM_SIM_SOURCE=$ROOT/probes/mle/teavm-engine/src/main/java/doomdb/mle/engine/SimulationEngineReachabilityProbe.java
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
  "$TEAVM_PROFILE" "$TEAVM_PATCH" "$TEAVM_INIT_DIET_PATCH" \
  "$TEAVM_INIT_DIET_RUNNER" "$TEAVM_INIT_PROFILE" "$TEAVM_MEMORY_CAL" \
  "$TEAVM_MEMORY_CAL_SQL" "$TEAVM_DISPATCH_BENCH" \
  "$TEAVM_DISPATCH_RUNNER" "$TEAVM_DISPATCH_AB" "$TEAVM_DIFFERENTIAL_RUNNER" \
  "$TEAVM_WORKER_CUTOVER_RUNNER" "$TEAVM_BROWSER_REPLICA_PROFILE" \
  "$TEAVM_WAN_RUNNER" \
  "$TEAVM_SIM_SOURCE" "$REPORT" "$TEAVM_REPORT" "$VERSIONS" \
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
[ -x "$TEAVM_WORKER_CUTOVER_RUNNER" ] || fail 'TeaVM worker cutover runner is not executable'
[ -x "$TEAVM_WAN_RUNNER" ] || fail 'TeaVM WAN matrix runner is not executable'
[ -x "$TEAVM_COOP" ] || fail 'TeaVM co-op differential generator is not executable'

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
grep -q 'emitted Math member is not allowlisted' "$TEAVM_BUILD" || fail 'emitted Math allowlist gate missing'
grep -Fq "Math.imul|Math.floor|Math.ceil|Math.round" "$TEAVM_BUILD" || fail 'exact Math operation allowlist missing'
grep -Fq "rg -F 'Math['" "$TEAVM_BUILD" || fail 'computed Math access fence missing'
grep -q 'Profiler.start' "$TEAVM_PROFILE" || fail 'Node ledger CPU profile missing'
grep -q '13272' "$TEAVM_PROFILE" || fail 'Node profile ledger-size fence missing'
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
for long_runner in "$TEAVM_MULTI_SOAK_RUNNER" "$TEAVM_WORKER_CUTOVER_RUNNER" \
  "$TEAVM_LEDGER_RUNNER" "$TEAVM_LIVE_MATRIX" "$HIDDEN_JIT_RUNNER"; do
  grep -q 'oracle-alert-window.sh' "$long_runner" ||
    fail "long diagnostic lacks Oracle alert-window gate: $long_runner"
done
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
grep -q '"inputBytecodeSha256": "631f3d7657b3b9521ed800d1b4ec518d4b6f102e5bf2a9f3e7caf1cb45624ecd"' "$VERSIONS" || fail 'TeaVM input bytecode pin missing'
grep -q '"mochaBytecodeSha256": "42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e"' "$VERSIONS" || fail 'TeaVM Mocha bytecode pin missing'
grep -q '"outputSha256": "e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b"' "$VERSIONS" || fail 'TeaVM output pin missing'
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

printf '%s\n' 'PASS PMLE-SOURCE (pure MLE, native PL/SQL, FFI, command boundary, and cleanup gates)'
