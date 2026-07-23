#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mkdir -p "$project/target"

profile="${1:-simulation-engine}"
case "$profile" in
  simulation-engine|simulation-engine-headless) ;;
  *) printf 'unsupported profile: %s\n' "$profile" >&2; exit 2 ;;
esac
jar="$project/target/mochadoom-ojvm.jar"
if [[ "$profile" == simulation-engine-headless ]]; then
  jar="$project/target/mochadoom-mle-simulation.jar"
fi
[[ -s "$jar" ]] || {
  printf 'required engine jar is missing: %s\n' "$jar" >&2
  exit 2
}
log="$project/target/$profile-build.log"
set +e
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -P"$profile" package >"$log" 2>&1
result=$?
set -e
if (( result == 0 )); then
  output="$project/target/javascript/doom-mle-$profile.js"
  test -s "$output"
  printf 'PASS PMLE-TEAVM-%s bytes=%s\n' "$profile" \
    "$(wc -c <"$output" | tr -d '[:space:]')"
else
  printf 'BLOCKER PMLE-TEAVM-%s status=%s log=%s\n' "$profile" "$result" "$log"
  rg -n -m 50 'SEVERE|ERROR|Unsupported|not found|not supported|failed|Exception' \
    "$log" || true
fi
exit "$result"
