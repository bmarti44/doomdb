#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
diagnostic="${1:-$spike/target/wasm/doom-wasm2js-authority.i64-diagnostic.log}"
patch="$spike/0004-canonical-save-low-word-workaround.patch"
wasm="$spike/target/wasm/doom-wasm2js-authority.wasm"
wasm2js="$spike/node_modules/.bin/wasm2js"
lowerer="$spike/lower-for-wasm2js.sh"
stem="$spike/target/wasm/doom-wasm2js-authority.serializer-workaround"
lowered="$stem.mvp.wasm"
translated="$stem.o0.mjs"
bundle="$stem.o0.bundle.mjs"
build_log="$stem.build.log"
tic0_log="$stem.tic0.log"
parity_log="$stem.100tic.log"
log="$stem.log"

for input in "$diagnostic" "$patch" "$wasm2js" "$lowerer"; do
  [[ -s "$input" ]] || {
    printf 'serializer workaround input missing: %s\n' "$input" >&2
    exit 1
  }
done
[[ "$(grep -c '^PMLE_WASM2JS_I64_DIAGNOSTIC|START|' "$diagnostic" || true)" == 1 &&
    "$(grep -c '^PMLE_WASM2JS_I64_DIAGNOSTIC|PASS|o0_parity=FAIL|classification=CANONICAL_SERIALIZER_CALL_BOUNDARY_HIGH_WORD_LOSS|' \
      "$diagnostic" || true)" == 1 &&
    "$(grep -Fxc \
      'PMLE_WASM2JS_SERIALIZER_WORKAROUND|REQUIRED|shape=object_to_high_int_no_long_call_boundary' \
      "$diagnostic" || true)" == 1 ]] || {
  printf '%s\n' \
    'serializer workaround requires one exact call-boundary diagnostic' >&2
  exit 1
}

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-differential[.]sh|[r]un-worker-cutover|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'serializer workaround refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'serializer workaround requires a quiet host:\n%s\n' \
    "$busy_host" >&2
  exit 1
}
for output in "$lowered" "$translated" "$bundle" "$build_log" "$tic0_log" \
    "$parity_log" "$log"; do
  [[ ! -e "$output" ]] || {
    printf 'refusing to overwrite serializer workaround evidence: %s\n' \
      "$output" >&2
    exit 1
  }
done

patch_sha="$(shasum -a 256 "$patch" | awk '{print $1}')"
DOOMDB_WASM2JS_SOURCE_PATCH="$patch" \
  "$spike/build.sh" | tee "$build_log"
grep -Eq \
  "^PASS PMLE-WASM2JS-TEAVM-BUILD .*source_patch_sha256=$patch_sha adapter_patch_sha256=none decps=YES$" \
  "$build_log"

"$lowerer" "$wasm" "$lowered"
"$wasm2js" -O0 "$lowered" -o "$translated"
node "$spike/bundle-wasm2js.mjs" "$translated" "$bundle"
DOOMDB_WASM2JS_ARTIFACT="$bundle" DOOMDB_WASM2JS_TICS=0 \
  node "$spike/run-node-parity.mjs" | tee "$tic0_log"
grep -q '^PASS PMLE-WASM2JS-NODE-PARITY tics=0 checkpoints=1 ' \
  "$tic0_log"
[[ "$(grep -c '^PASS PMLE-WASM2JS-NODE-PARITY ' "$tic0_log" || true)" == 1 ]]
! grep -q '^FAIL PMLE-WASM2JS-NODE-PARITY' "$tic0_log"
DOOMDB_WASM2JS_ARTIFACT="$bundle" DOOMDB_WASM2JS_TICS=100 \
  node "$spike/run-node-parity.mjs" | tee "$parity_log"
grep -q '^PASS PMLE-WASM2JS-NODE-PARITY tics=100 checkpoints=101 ' \
  "$parity_log"
[[ "$(grep -c '^PASS PMLE-WASM2JS-NODE-PARITY ' "$parity_log" || true)" == 1 ]]
! grep -q '^FAIL PMLE-WASM2JS-NODE-PARITY' "$parity_log"

{
  printf 'PMLE_WASM2JS_SERIALIZER_WORKAROUND|PASS'
  printf '|classification=CANDIDATE_FOR_DIRECT_MLE_RANK'
  printf '|source_patch_sha256=%s' "$patch_sha"
  printf '|wasm_sha256=%s' "$(shasum -a 256 "$wasm" | awk '{print $1}')"
  printf '|bundle_sha256=%s' "$(shasum -a 256 "$bundle" | awk '{print $1}')"
  printf '|tic0_log_sha256=%s' "$(shasum -a 256 "$tic0_log" | awk '{print $1}')"
  printf '|parity_log_sha256=%s\n' \
    "$(shasum -a 256 "$parity_log" | awk '{print $1}')"
} | tee "$log"
