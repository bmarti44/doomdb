#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SPIKE=$ROOT/probes/mle/teavm-engine/wasm2js
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

if git -C "$ROOT" ls-files 'probes/mle/teavm-engine/wasm2js/target' |
    grep -q .; then
  printf 'generated wasm2js target output is tracked\n' >&2
  exit 1
fi

printf 'PASS PMLE-WASM2JS-SOURCE verdict=REJECT_CURRENT_TRANSLATOR\n'
