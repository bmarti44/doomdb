#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SPIKE=$ROOT/probes/mle/teavm-engine/wasm2js
MLE_WRAPPER=$SPIKE/mle-rank-wrapper.mjs
MLE_WRAPPER_TEST=$SPIKE/test-mle-rank-wrapper.mjs
MLE_INSTALL=$SPIKE/install-mle-rank.sh
MLE_CLEANUP=$SPIKE/cleanup-mle-rank.sql
MLE_BENCHMARK=$SPIKE/benchmark-mle-rank.sql
MLE_COMPARATOR=$SPIKE/compare-mle-rank.mjs
MLE_PARITY_EXTRACTOR=$SPIKE/extract-node-parity.mjs
MLE_DB_PARITY_EXTRACTOR=$SPIKE/extract-mle-parity.mjs
MLE_RUNNER=$SPIKE/run-mle-rank.sh
REPORT=$ROOT/artifacts/performance/pmle-wasm2js/REPORT.md
LOG=$ROOT/artifacts/performance/pmle-wasm2js/run-2026-07-24.log

grep -q 'b3a245b7d9034ff35cdfab2def057a3d4f256efb' \
  "$SPIKE/build-teavm-singlethread.sh"
grep -q '0.13.1-doomdb-singlethread' "$SPIKE/pom.xml"
grep -q 'CoroutineTransformation' "$SPIKE/0001-teavm-singlethread-no-cps.patch"
grep -q '"binaryen": "131.0.0"' "$SPIKE/package-lock.json"
grep -q '^FAIL PMLE-WASM2JS-NODE-PARITY|tic=0|differences=236|' "$LOG"
grep -q '^PMLE_WASM2JS_MLE_RANK|NOT_RUN|' "$LOG"
grep -q '^PMLE_WASM2JS_VERDICT|REJECT_CURRENT_TRANSLATOR|' "$LOG"
grep -q 'native Wasm identity' "$REPORT"
grep -q 'accept no alternate Wasm input path' \
  "$SPIKE/run-i64-lowering-diagnostics.sh"
grep -q 'exact_call_boundary=1' "$SPIKE/run-i64-lowering-diagnostics.sh"
grep -q "== 6 ]] || exact_call_boundary=0" \
  "$SPIKE/run-i64-lowering-diagnostics.sh"
grep -q 'requires one exact call-boundary diagnostic' \
  "$SPIKE/run-serializer-workaround.sh"
grep -q "grep -c '\^PASS PMLE-WASM2JS-NODE-PARITY '" \
  "$SPIKE/run-serializer-workaround.sh"
node --check "$MLE_WRAPPER"
node "$MLE_WRAPPER_TEST" >/dev/null
grep -q "import \\* as engine from 'doom_wasm2js_engine'" "$MLE_WRAPPER"
grep -q 'new Uint8Array(engine.memory.buffer' "$MLE_WRAPPER"
grep -q 'Recreate the view for every chunk' "$MLE_WRAPPER"
grep -q 'engine.doom_step_authority(activePlayers, membershipMask)' \
  "$MLE_WRAPPER"
grep -q 'length > 32767' "$MLE_WRAPPER"
grep -q 'wasm2js i64 lowering mismatch' "$MLE_WRAPPER"
[ -x "$MLE_INSTALL" ]
sh -n "$MLE_INSTALL"
"$MLE_INSTALL" --self-test >/dev/null
grep -q 'CANDIDATE_FOR_DIRECT_MLE_RANK' "$MLE_INSTALL"
grep -q 'adapter_patch_sha256=' "$MLE_INSTALL"
grep -q 'wasm_sha256=' "$MLE_INSTALL"
grep -q 'tic0_log_sha256=' "$MLE_INSTALL"
grep -q 'parity_log_sha256=' "$MLE_INSTALL"
grep -q 'grep -Fxc "$workaround_terminal"' "$MLE_INSTALL"
grep -q 'dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)' "$MLE_INSTALL"
grep -q 'PMLE_WASM2JS_MLE_STAGING|PASS' "$MLE_INSTALL"
grep -q 'doom_wasm2js_rank_lowering' "$MLE_INSTALL"
grep -q '\[r\]un-decps-ledger' "$MLE_INSTALL"
grep -q 'drop mle module doom_wasm2js_rank_bridge' "$MLE_CLEANUP"
grep -q 'drop mle module doom_wasm2js_rank_engine' "$MLE_CLEANUP"
grep -q 'c_parity_tics constant pls_integer:=100' "$MLE_BENCHMARK"
grep -q 'c_rank_tics constant pls_integer:=5250' "$MLE_BENCHMARK"
grep -q 'PMLE_WASM2JS_MLE_PARITY|PASS' "$MLE_BENCHMARK"
grep -q 'PMLE_WASM2JS_MLE_RANK|PASS' "$MLE_BENCHMARK"
node "$MLE_COMPARATOR" --self-test >/dev/null
grep -q 'minimum >= 2' "$MLE_COMPARATOR"
grep -q 'minimum < 1.5' "$MLE_COMPARATOR"
grep -q 'rank terminal is inconsistent with tic samples' "$MLE_COMPARATOR"
grep -q 'wasm2js memory windows: expected' "$MLE_COMPARATOR"
grep -q 'artifact, parity, samples, terminal, and windows are out of order' \
  "$MLE_COMPARATOR"
grep -q 'baseline artifact, samples, and terminal are out of order' \
  "$MLE_COMPARATOR"
grep -q 'de-CPS baseline artifact is not the approved rank parent' \
  "$MLE_COMPARATOR"
grep -q 'candidate_sha256=' "$MLE_COMPARATOR"
grep -q 'linear_memory_max_bytes=' "$MLE_COMPARATOR"
grep -q 'canonical chunk short' "$MLE_BENCHMARK"
node "$MLE_PARITY_EXTRACTOR" --self-test >/dev/null
node "$MLE_DB_PARITY_EXTRACTOR" --self-test >/dev/null
[ -x "$MLE_RUNNER" ]
sh -n "$MLE_RUNNER"
grep -q 'PMLE_WASM2JS_RANK_EXECUTE' "$MLE_RUNNER"
grep -q '\[r\]un-decps-ledger' "$MLE_RUNNER"
grep -q 'oracle-alert-window.sh' "$MLE_RUNNER"
grep -q 'artifact-metadata.sql' "$MLE_RUNNER"
grep -q 'PMLE_WASM2JS_MLE_CLEANUP|PASS|objects=0' "$MLE_RUNNER"
grep -q 'cleanup_or_alert_unproven' "$MLE_RUNNER"
grep -q 'safe_to_start_pool=0' "$MLE_RUNNER"
grep -q 'doom_match_worker.start_warm_pool' "$MLE_RUNNER"
grep -q 'PMLE_WASM2JS_MLE_CAPACITY|RESTORED|slots=' "$MLE_RUNNER"
grep -q 'PMLE-WASM2JS-MLE-RANK' "$MLE_RUNNER"
wasm_pool_restart_line=$(grep -n \
  '^  doom_match_worker.start_warm_pool;' "$MLE_RUNNER" |
  tail -1 | cut -d: -f1)
wasm_terminal_line=$(grep -n \
  "printf 'PASS PMLE-WASM2JS-MLE-RANK" "$MLE_RUNNER" |
  tail -1 | cut -d: -f1)
wasm_disarm_line=$(grep -n '^trap - EXIT$' "$MLE_RUNNER" |
  tail -1 | cut -d: -f1)
[ "$wasm_pool_restart_line" -lt "$wasm_terminal_line" ] ||
  { printf 'wasm2js MLE rank can claim PASS before capacity restore\n' >&2;
    exit 1; }
[ "$wasm_pool_restart_line" -lt "$wasm_disarm_line" ] &&
  [ "$wasm_disarm_line" -lt "$wasm_terminal_line" ] ||
  { printf 'wasm2js MLE rank terminal trap ordering is unsafe\n' >&2;
    exit 1; }

if git -C "$ROOT" ls-files 'probes/mle/teavm-engine/wasm2js/target' |
    grep -q .; then
  printf 'generated wasm2js target output is tracked\n' >&2
  exit 1
fi

printf 'PASS PMLE-WASM2JS-SOURCE verdict=REJECT_CURRENT_TRANSLATOR\n'
