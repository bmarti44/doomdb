#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
iwad="$project/target/iwad-smoke/freedoom1.wad"
table_pack="$project/target/canonical-runtime-v2.bin"
tag="${PMLE_INIT_PROFILE_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid profile tag\n' >&2;exit 2; }
for input in "$artifact" "$iwad" "$table_pack"; do
  [[ -s "$input" ]] || { printf 'profile prerequisite missing: %s\n' "$input" >&2;exit 2; }
done

output_dir="$project/target/init-profile"
mkdir -p "$output_dir"
profile="$output_dir/init-${tag}.cpuprofile"
log="$output_dir/init-${tag}.log"
[[ ! -e "$profile" && ! -e "$log" ]] ||
  { printf 'init profile output already exists for %s\n' "$tag" >&2;exit 1; }

started="$(node -e 'process.stdout.write(process.hrtime.bigint().toString())')"
PMLE_SIMULATION_ARTIFACT="$artifact" \
node --cpu-prof --cpu-prof-dir="$output_dir" \
  --cpu-prof-name="$(basename "$profile")" \
  "$project/run-simulation-node.mjs" "$iwad" "$table_pack" 2>&1 |
while IFS= read -r line || [[ -n "$line" ]]; do
  now="$(node -e 'process.stdout.write(process.hrtime.bigint().toString())')"
  elapsed_ms=$(( (now - started) / 1000000 ))
  printf 'PMLE_INIT_PROFILE_TS|elapsed_ms=%s|%s\n' "$elapsed_ms" "$line"
done | tee "$log"

[[ -s "$profile" ]] || { printf 'V8 CPU profile was not produced\n' >&2;exit 1; }
printf 'PMLE_INIT_PROFILE|PASS|artifact_bytes=%s|artifact_sha256=%s|profile=%s|log=%s\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "${profile#$root/}" "${log#$root/}"
