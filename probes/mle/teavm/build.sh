#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm"
mkdir -p "$project/target"
"$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$project/target/mochadoom-ojvm.jar" "$project/target/mochadoom-ojvm.json"
docker run --rm -v "$root:/work" -v doomdb-maven-cache:/root/.m2 \
  -w /work/probes/mle/teavm \
  maven:3.9.11-eclipse-temurin-17 mvn -B -DskipTests package
test -s "$project/target/javascript/doom-mle-probe.js"
printf 'PASS PMLE-TEAVM bytes=%s\n' "$(wc -c <"$project/target/javascript/doom-mle-probe.js" | tr -d '[:space:]')"
