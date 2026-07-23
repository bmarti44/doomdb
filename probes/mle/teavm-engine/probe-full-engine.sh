#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mkdir -p "$project/target"
[[ -s "$project/target/mochadoom-ojvm.jar" ]] || \
  DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
    DOOMDB_MOCHA_EXTRA_PATCH="$project/0001-teavm-no-console-handler.patch" \
    "$root/scripts/mochadoom/build-ojvm-jar.sh" \
    "$project/target/mochadoom-ojvm.jar" "$project/target/mochadoom-ojvm.json"
set +e
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Pfull-engine package \
  >"$project/target/full-engine-build.log" 2>&1
status=$?
set -e
if (( status == 0 )); then
  test -s "$project/target/javascript/doom-mle-full-engine.js"
  printf 'PASS PMLE-TEAVM-FULL-ENGINE-ANALYSIS bytes=%s\n' \
    "$(wc -c <"$project/target/javascript/doom-mle-full-engine.js" | tr -d '[:space:]')"
else
  printf 'EXPECTED_BLOCKER PMLE-TEAVM-FULL-ENGINE status=%s log=%s\n' \
    "$status" "$project/target/full-engine-build.log"
  rg -n -m 40 'SEVERE|ERROR|Unsupported|not found|not supported|failed|Exception' \
    "$project/target/full-engine-build.log" || true
fi
exit "$status"
