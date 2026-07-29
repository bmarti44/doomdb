#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$root/probes/mle/free-live-teavm"
artifact="$project/target/javascript/doom-mle-free-live-world-raster.js"
pack_dir="$project/target/world-raster-pack"
base_pack="$pack_dir/free-live-render-v4.pack"
pack="$pack_dir/free-live-render.pack"
live_pack="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
poses="$root/probes/mle/target/free-live-renderer/live-dm.state-v3.bin"
benchmark="$project/target/world-raster-benchmark.sql"

node "$project/build-world-raster-source.mjs" "$project"
mkdir -p "$pack_dir"
node "$project/target/world-raster-tools/build-free-live-render-pack.mjs" \
  "$root" "$poses" "$base_pack"
node "$project/build-world-live-pack.mjs" "$base_pack" "$live_pack" "$pack"
node "$project/build-world-raster-benchmark.mjs" \
  "$root/probes/mle/benchmark-oci-free-live-renderer-teavm-raster.sql" \
  "$benchmark"
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/free-live-teavm maven:3.9.11-eclipse-temurin-17 \
  mvn -B -f pom-world-raster.xml -DskipTests package
[[ -s "$artifact" && ! -L "$artifact" ]] || exit 1
printf 'PMLE_FREE_LIVE_WORLD_BUILD|PASS|bytes=%s|sha256=%s|teavm=0.15.0|optimization=ADVANCED\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')"
printf 'PMLE_FREE_LIVE_WORLD_PACK|PASS|bytes=%s|sha256=%s|version=5|dynamics=sectors+sidedefs\n' \
  "$(wc -c <"$pack" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$pack" | awk '{print $1}')"
