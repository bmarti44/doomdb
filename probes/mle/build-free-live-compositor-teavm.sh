#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$root/probes/mle/free-live-teavm"
artifact="$project/target/javascript/doom-mle-free-live-compositor.js"
pack="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
assets="$root/probes/mle/target/free-live-renderer/assets-v1"

for input in \
  "$project/pom-compositor.xml" \
  "$project/build-compositor-source.mjs" \
  "$project/src/main/java/doomdb/mle/renderer/FreeLiveRendererReachabilityProbe.java" \
  "$project/src/main/java/doomdb/mle/renderer/FreeLiveCompositorModule.java" \
  "$pack" "$assets/sprite_patch.bin" "$assets/ui_patch.bin"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'compositor input missing: %s\n' "$input" >&2;exit 2; }
done

node "$project/build-compositor-source.mjs" "$project"
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/free-live-teavm maven:3.9.11-eclipse-temurin-17 \
  mvn -B -f pom-compositor.xml -DskipTests package
[[ -s "$artifact" && ! -L "$artifact" ]] || exit 1
printf 'PMLE_FREE_LIVE_COMPOSITOR_BUILD|PASS|bytes=%s|sha256=%s|pack_sha256=%s|teavm=0.15.0|optimization=ADVANCED\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$(shasum -a 256 "$pack" | awk '{print $1}')"
