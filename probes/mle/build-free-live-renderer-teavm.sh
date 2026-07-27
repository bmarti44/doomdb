#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$root/probes/mle/free-live-teavm"
source_file="$project/src/main/java/doomdb/mle/renderer/FreeLiveRendererReachabilityProbe.java"
artifact="$project/target/javascript/doom-mle-free-live-renderer.js"

for input in "$project/pom.xml" "$source_file"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'generated renderer input missing: %s\n' "$input" >&2;exit 2; }
done
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/free-live-teavm maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests package
[[ -s "$artifact" && ! -L "$artifact" ]] || exit 1
printf 'PMLE_FREE_LIVE_TEAVM_BUILD|PASS|bytes=%s|sha256=%s|source_sha256=%s|teavm=0.15.0|optimization=ADVANCED\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$(shasum -a 256 "$source_file" | awk '{print $1}')"
