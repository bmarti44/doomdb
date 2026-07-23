#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mkdir -p "$project/target"
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
  DOOMDB_MOCHA_EXTRA_PATCH="$project/0001-teavm-no-console-handler.patch" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$project/target/mochadoom-ojvm.jar" "$project/target/mochadoom-ojvm.json"
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests package
test -s "$project/target/javascript/doom-mle-engine-slice.js"
node "$project/run-node.mjs"
printf 'PASS PMLE-TEAVM-ENGINE-BUILD bytes=%s\n' \
  "$(wc -c <"$project/target/javascript/doom-mle-engine-slice.js" | tr -d '[:space:]')"
