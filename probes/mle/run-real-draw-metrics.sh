#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
target="$probe/target/real-draw-metrics"
evidence="$root/artifacts/performance/pmle-free-live-frames"
log="$evidence/real-draw-metrics-live-dm-2026-07-26.log"
iwad="$root/probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad"
table_pack="$root/probes/mle/teavm-engine/target/canonical-runtime-v2.bin"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
expanded="$target/live-dm-2026-07-23.expanded.bin"
jar="$target/mochadoom-real-draw-metrics.jar"
metadata="$target/mochadoom-real-draw-metrics.json"
poses="$target/live-dm-2026-07-23.poses.bin"

for input in "$iwad" "$table_pack" "$fixture"; do
  [[ -s "$input" ]] || {
    printf 'real-draw input missing: %s\n' "$input" >&2
    exit 2
  }
done
mkdir -p "$target" "$evidence"
[[ ! -e "$log" ]] || {
  printf 'real-draw evidence already exists: %s\n' "$log" >&2
  exit 1
}
exec > >(tee "$log") 2>&1
node "$probe/expand-real-draw-fixture.mjs" "$fixture" "$expanded"

DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=830 \
DOOMDB_MOCHA_EXTRA_PATCH="$probe/teavm-engine/0002-teavm-simulation-headless.patch,$probe/teavm-engine/0003-teavm-presentation-compat.patch,$probe/teavm-engine/0004-teavm-authority-init-diet.patch,$probe/teavm-engine/0005-teavm-statusbar-compat.patch,$probe/mochadoom-draw-metrics.patch" \
DOOMDB_MOCHA_EXTRA_ADAPTER_SOURCE="$probe/java" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" "$jar" "$metadata"

docker run --rm \
  -v "$jar:/work/metrics.jar:ro" \
  -v "$iwad:/work/freedoom1.wad:ro" \
  -v "$expanded:/work/stream.bin:ro" \
  -v "$table_pack:/work/tables.bin:ro" \
  -v "$target:/work/out" \
  eclipse-temurin:17-jre \
  java -cp /work/metrics.jar doomdb.mocha.DoomDbRealDrawMetricsMain \
  /work/freedoom1.wad /work/stream.bin /work/tables.bin \
  /work/out/live-dm-2026-07-23.poses.bin

[[ "$(wc -c <"$poses" | tr -d '[:space:]')" == 63000 ]] || {
  printf 'real-draw pose capture length mismatch\n' >&2
  exit 1
}
