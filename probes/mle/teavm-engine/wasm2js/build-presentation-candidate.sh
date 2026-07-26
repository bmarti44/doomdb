#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patch="$spike/0004-canonical-save-low-word-workaround.patch"
wasm="$spike/target/wasm/doom-wasm2js-authority.wasm"
stem="$spike/target/wasm/doom-wasm2js-presentation"
lowered="$stem.mvp.wasm"
translated="$stem.o0.mjs"
bundle="$stem.o0.bundle.mjs"
build_log="$stem.build.log"
terminal="$stem.log"

for input in "$patch" "$spike/lower-for-wasm2js.sh" \
    "$spike/node_modules/.bin/wasm2js"; do
  [[ -s "$input" ]] || {
    printf 'presentation wasm2js input is unavailable: %s\n' "$input" >&2
    exit 2
  }
done
for output in "$lowered" "$translated" "$bundle" "$build_log" "$terminal"; do
  [[ ! -e "$output" ]] || {
    printf 'refusing to overwrite presentation candidate: %s\n' "$output" >&2
    exit 1
  }
done

patch_sha="$(shasum -a 256 "$patch" | awk '{print $1}')"
DOOMDB_WASM2JS_SOURCE_PATCH="$patch" \
  "$spike/build.sh" | tee "$build_log"
grep -Eq \
  "^PASS PMLE-WASM2JS-TEAVM-BUILD .*source_patch_sha256=$patch_sha adapter_patch_sha256=none decps=YES$" \
  "$build_log"

"$spike/lower-for-wasm2js.sh" "$wasm" "$lowered"
"$spike/node_modules/.bin/wasm2js" -O0 "$lowered" -o "$translated"
node "$spike/bundle-wasm2js.mjs" "$translated" "$bundle"

printf 'PMLE_WASM2JS_PRESENTATION_BUILD|PASS|source_patch_sha256=%s|wasm_sha256=%s|bundle_sha256=%s|bundle_bytes=%s\n' \
  "$patch_sha" \
  "$(shasum -a 256 "$wasm" | awk '{print $1}')" \
  "$(shasum -a 256 "$bundle" | awk '{print $1}')" \
  "$(wc -c <"$bundle" | tr -d '[:space:]')" | tee "$terminal"
