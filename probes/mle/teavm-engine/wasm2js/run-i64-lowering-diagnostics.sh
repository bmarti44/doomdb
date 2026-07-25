#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wasm="$spike/target/wasm/doom-wasm2js-authority.wasm"
stem="$spike/target/wasm/doom-wasm2js-authority.i64-diagnostic"
wasm2js="$spike/node_modules/.bin/wasm2js"
wasm_dis="$spike/node_modules/.bin/wasm-dis"
translated="$stem.o0.mjs"
bundle="$stem.o0.bundle.mjs"
wat="$stem.wat"
inspection="$stem.serializer-inspection.txt"
build_log="$stem.build.log"
parity_log="$stem.o0-parity.log"
log="$stem.log"

[[ $# == 0 ]] || {
  printf '%s\n' \
    'wasm2js i64 diagnostics accept no alternate Wasm input path' >&2
  exit 2
}

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-live-command-matrix-mle|[r]un-decps-rank-mle/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'wasm2js i64 diagnostics refuse a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'wasm2js i64 diagnostics require a quiet host:\n%s\n' \
    "$busy_host" >&2
  exit 1
}

for input in "$wasm2js" "$wasm_dis"; do
  test -s "$input" || {
    printf 'missing wasm2js diagnostic input: %s\n' "$input" >&2
    exit 1
  }
done
for output in "$translated" "$bundle" "$wat" "$inspection" "$build_log" \
    "$parity_log" "$log"; do
  [[ ! -e "$output" ]] || {
    printf 'refusing to overwrite wasm2js diagnostic evidence: %s\n' \
      "$output" >&2
    exit 1
  }
done

"$spike/build.sh" | tee "$build_log"
[[ "$(grep -Ec \
    '^PASS PMLE-WASM2JS-TEAVM-BUILD .*patch_set_sha256=[0-9a-f]{64} adapter_patch_sha256=none decps=YES$' \
    "$build_log" || true)" == 1 &&
    "$(grep -c '^PASS PMLE-WASM2JS-TEAVM-BUILD ' \
      "$build_log" || true)" == 1 ]] || {
  printf '%s\n' 'wasm2js i64 diagnostic build terminal is ambiguous' >&2
  exit 1
}
test -s "$wasm"

{
  printf 'PMLE_WASM2JS_I64_DIAGNOSTIC|START'
  printf '|input_sha256=%s' "$(shasum -a 256 "$wasm" | awk '{print $1}')"
  printf '|build_sha256=%s' "$(shasum -a 256 "$build_log" | awk '{print $1}')"
  printf '|binaryen_version=%s' "$("$wasm2js" --version | tr -d '\r\n')"
  printf '|host_quiet=YES\n'

  # This is an optimizer-reordering discriminator. It explicitly disables
  # Binaryen optimization while retaining wasm2js's required lowering passes.
  "$wasm2js" -O0 "$wasm" -o "$translated"
  node "$spike/bundle-wasm2js.mjs" "$translated" "$bundle"
  set +e
  DOOMDB_WASM2JS_ARTIFACT="$bundle" DOOMDB_WASM2JS_TICS=0 \
    node "$spike/run-node-parity.mjs" 2>&1 | tee "$parity_log"
  parity_status=${PIPESTATUS[0]}
  set -e
  if [[ "$parity_status" == 0 ]]; then
    printf '%s\n' 'PMLE_WASM2JS_O0_PARITY|PASS|tics=0'
  else
    printf 'PMLE_WASM2JS_O0_PARITY|FAIL|tics=0|exit_status=%s\n' \
      "$parity_status"
  fi

  # Preserve the pre-translation Wasm around the canonical serializer exports
  # and every i64 operation/name that can identify the high-half call boundary.
  "$wasm_dis" --emit-module-names "$wasm" -o "$wat"
  {
    printf '%s\n' 'PMLE_WASM2JS_SERIALIZER_DISASSEMBLY|BEGIN'
    rg -n -C 12 \
      'doom_canonical_(length|ref)|canonical(State|Material)|i64[.]' "$wat"
    printf '%s\n' 'PMLE_WASM2JS_SERIALIZER_DISASSEMBLY|END'
  } >"$inspection"
  test -s "$inspection"
  grep -q 'doom_canonical_' "$inspection"
  grep -q 'i64[.]' "$inspection"

  i64_class=OTHER_I64_OR_SERIALIZER_FAILURE
  exact_call_boundary=1
  [[ "$(grep -c '^PMLE_WASM2JS_I64_REDUCTION_CASE|' \
      "$parity_log" || true)" == 6 ]] || exact_call_boundary=0
  for case_ in constant field field_copy array flag_or; do
    [[ "$(grep -c \
      "^PMLE_WASM2JS_I64_REDUCTION_CASE|PASS|case=$case_|" \
      "$parity_log" || true)" == 1 ]] || exact_call_boundary=0
  done
  [[ "$(grep -c \
    '^PMLE_WASM2JS_I64_REDUCTION_CASE|FAIL|case=call|' \
    "$parity_log" || true)" == 1 ]] || exact_call_boundary=0
  if [[ "$parity_status" != 0 && "$exact_call_boundary" == 1 ]]; then
    i64_class=CALL_BOUNDARY_HIGH_WORD_LOSS
    printf '%s\n' \
      'PMLE_WASM2JS_SERIALIZER_WORKAROUND|REQUIRED|shape=object_to_high_int_no_long_call_boundary'
  elif [[ "$parity_status" == 0 ]]; then
    i64_class=O0_PARITY_EXACT
  fi

  printf 'PMLE_WASM2JS_I64_DIAGNOSTIC|PASS'
  printf '|o0_parity=%s' "$([[ "$parity_status" == 0 ]] && printf PASS || printf FAIL)"
  printf '|classification=%s' "$i64_class"
  printf '|o0_sha256=%s' "$(shasum -a 256 "$bundle" | awk '{print $1}')"
  printf '|wat_sha256=%s' "$(shasum -a 256 "$wat" | awk '{print $1}')"
  printf '|inspection_sha256=%s\n' \
    "$(shasum -a 256 "$inspection" | awk '{print $1}')"
} | tee "$log"
