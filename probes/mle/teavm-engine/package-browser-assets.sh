#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
destination="$root/client/dist/play"
authority="$project/target/javascript/doom-mle-simulation-engine-headless.js"
presentation="$project/target/javascript/doom-mle-presentation-engine-headless.js"
tables="$project/target/canonical-runtime-v2.bin"
iwad="$project/target/iwad-smoke/freedoom1.wad"

for artifact in "$authority" "$presentation" "$tables" "$iwad"; do
  [[ -s "$artifact" ]] || { printf 'browser artifact missing: %s\n' "$artifact" >&2;exit 2; }
done

verify_copy() {
  local source="$1" destination_path="$2" expected="$3"
  local actual
  actual="$(shasum -a 256 "$source" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    printf 'browser artifact SHA-256 mismatch: %s actual=%s expected=%s\n' \
      "$source" "$actual" "$expected" >&2
    exit 1
  }
  cp "$source" "$destination_path"
  [[ "$(shasum -a 256 "$destination_path" | awk '{print $1}')" == "$expected" ]]
}

mkdir -p "$destination"
verify_copy "$authority" "$destination/doom-mle-authority-06ac33331d9a.js" \
  06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0
verify_copy "$presentation" "$destination/doom-mle-presentation-bd35d27784db.js" \
  bd35d27784db2332e1c06f08a7eeb8940b1a17a732bfb45de0b4b3b42d419b83
verify_copy "$tables" "$destination/canonical-runtime-v2-058cd0df9444.bin" \
  058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44
verify_copy "$iwad" "$destination/freedoom1-7323bcc168c5.bin" \
  7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d
printf 'PASS PMLE-BROWSER-ASSETS authority=%s presentation=%s iwad_bytes=%s\n' \
  06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0 \
  bd35d27784db2332e1c06f08a7eeb8940b1a17a732bfb45de0b4b3b42d419b83 \
  "$(wc -c <"$iwad" | tr -d '[:space:]')"
