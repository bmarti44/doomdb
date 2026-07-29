#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$root/probes/mle/free-live-teavm"
artifact="$project/target/javascript/doom-mle-free-live-unified-renderer.js"
optimization="${PMLE_FREE_LIVE_OPTIMIZATION:-ADVANCED}"
[[ "$optimization" == ADVANCED || "$optimization" == FULL ]] || {
  printf '%s\n' 'PMLE_FREE_LIVE_OPTIMIZATION must be ADVANCED or FULL' >&2
  exit 2
}

node "$project/build-world-raster-source.mjs" "$project"
node "$project/build-compositor-source.mjs" "$project"
node "$project/build-unified-source.mjs" "$project"
docker run --rm --cpus 2 --memory 2g \
  -v "$root:/work" -w /work/probes/mle/free-live-teavm \
  -v doomdb-maven-cache:/root/.m2 \
  maven:3.9.11-eclipse-temurin-17 \
  mvn -B -f pom-unified.xml -DskipTests \
  -Dteavm.optimizationLevel="$optimization" package
[[ -s "$artifact" && ! -L "$artifact" ]] || exit 1
if grep -Eq \
    'wall command buffer overflow|resolved wall command buffer overflow|native wall tape overflow|rasterPixelWrites' \
    "$artifact"; then
  printf '%s\n' \
    'PMLE_FREE_LIVE_UNIFIED_BUILD|FAIL|reason=live_raster_dead_graph' >&2
  exit 1
fi
printf '%s\n' 'PMLE_FREE_LIVE_LIVE_RASTER_SPECIALIZATION|PASS'
node "$root/probes/mle/verify-native-byte-array-view.mjs" \
  "$artifact" frameNativeByRef
printf 'PMLE_FREE_LIVE_UNIFIED_BUILD|PASS|bytes=%s|sha256=%s|teavm=0.15.0|optimization=%s\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$optimization"
