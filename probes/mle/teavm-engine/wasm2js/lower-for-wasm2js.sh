#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wasm_opt="$spike/node_modules/.bin/wasm-opt"

[[ $# == 2 ]] || {
  printf 'usage: %s INPUT.wasm OUTPUT.wasm\n' "$0" >&2
  exit 2
}

input="$1"
output="$2"

for path in "$wasm_opt" "$input"; do
  [[ -s "$path" ]] || {
    printf 'wasm2js lowering input missing: %s\n' "$path" >&2
    exit 1
  }
done
[[ ! -e "$output" ]] || {
  printf 'refusing to overwrite lowered Wasm: %s\n' "$output" >&2
  exit 1
}

# TeaVM legacy Wasm uses bulk-memory and nontrapping float-to-int operations.
# Binaryen's wasm2js pass validates after i64 lowering, where those operations
# otherwise have invalid lowered result types. Lower both features first.
# Do not use --all-features here: it enables memory64/multi-memory and makes
# the bulk-memory lowering itself fail.
"$wasm_opt" \
  --enable-bulk-memory \
  --enable-nontrapping-float-to-int \
  --llvm-nontrapping-fptoint-lowering \
  --llvm-memory-copy-fill-lowering \
  "$input" \
  -o "$output"

printf 'PMLE_WASM2JS_MVP_LOWERING|PASS'
printf '|input_sha256=%s' "$(shasum -a 256 "$input" | awk '{print $1}')"
printf '|output_sha256=%s' "$(shasum -a 256 "$output" | awk '{print $1}')"
printf '|output_bytes=%s\n' "$(wc -c <"$output" | tr -d '[:space:]')"
