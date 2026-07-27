#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
target="$probe/target/free-live-renderer"
evidence="$root/artifacts/performance/pmle-free-live-frames"
log="$evidence/real-render-state-v3b-2026-07-26.log"
iwad="$probe/teavm-engine/target/iwad-smoke/freedoom1.wad"
tables="$probe/teavm-engine/target/canonical-runtime-v2.bin"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
stream="$target/live-dm.expanded.bin"
poses="$target/live-dm.state-v3.bin"
jar="$target/metrics.jar"
metadata="$target/metrics.json"

for input in "$iwad" "$tables" "$fixture"; do [[ -s "$input" ]] || exit 2; done
[[ ! -e "$log" ]] || { printf 'pose evidence exists: %s\n' "$log" >&2;exit 1; }
mkdir -p "$target" "$evidence"
exec > >(tee "$log") 2>&1
node "$probe/expand-real-draw-fixture.mjs" "$fixture" "$stream"
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=830 \
DOOMDB_MOCHA_EXTRA_PATCH="$probe/teavm-engine/0002-teavm-simulation-headless.patch,$probe/teavm-engine/0003-teavm-presentation-compat.patch,$probe/teavm-engine/0004-teavm-authority-init-diet.patch,$probe/teavm-engine/0005-teavm-statusbar-compat.patch,$probe/mochadoom-draw-metrics.patch" \
DOOMDB_MOCHA_EXTRA_ADAPTER_SOURCE="$probe/java" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" "$jar" "$metadata"
docker run --rm \
  -v "$jar:/work/metrics.jar:ro" -v "$iwad:/work/freedoom1.wad:ro" \
  -v "$stream:/work/stream.bin:ro" -v "$tables:/work/tables.bin:ro" \
  -v "$target:/work/out" eclipse-temurin:17-jre \
  java -cp /work/metrics.jar doomdb.mocha.DoomDbRealDrawMetricsMain \
    /work/freedoom1.wad /work/stream.bin /work/tables.bin \
    /work/out/live-dm.state-v3.bin --extended-poses
[[ "$(wc -c <"$poses" | tr -d '[:space:]')" == 168000 ]]
node "$probe/build-free-live-render-pack.mjs" "$root" "$poses" \
  "$target/free-live-render.pack"
