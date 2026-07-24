#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
spike="$root/probes/mle/teavm-engine/wasm2js"
source_dir="$spike/target/teavm-singlethread/source"
commit='b3a245b7d9034ff35cdfab2def057a3d4f256efb'
coordinate='0.13.1-doomdb-singlethread'

mkdir -p "$(dirname "$source_dir")"
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --quiet https://github.com/konsoletyper/teavm.git "$source_dir"
fi
git -C "$source_dir" fetch --quiet origin "$commit"
git -C "$source_dir" checkout --quiet --detach "$commit"
test "$(git -C "$source_dir" rev-parse HEAD)" = "$commit"
if git -C "$source_dir" apply --check \
    "$spike/0001-teavm-singlethread-no-cps.patch"; then
  git -C "$source_dir" apply "$spike/0001-teavm-singlethread-no-cps.patch"
elif git -C "$source_dir" apply --reverse --check \
    "$spike/0001-teavm-singlethread-no-cps.patch"; then
  printf 'PMLE_WASM2JS_TEAVM_PATCH|ALREADY_APPLIED\n'
else
  printf 'TeaVM source does not match the pinned single-thread patch\n' >&2
  exit 1
fi

docker run --rm \
  -v doomdb-maven-cache:/root/.m2 \
  -v "$source_dir:/src" \
  -w /src \
  maven:3.9.11-eclipse-temurin-17 \
  mvn -B -ntp -DskipTests -pl core -am install

docker run --rm \
  -v doomdb-maven-cache:/root/.m2 \
  -v "$source_dir:/src" \
  -w /src \
  maven:3.9.11-eclipse-temurin-17 \
  mvn -B -ntp install:install-file \
    -Dfile=core/target/teavm-core-0.13.1.jar \
    -DgroupId=org.teavm -DartifactId=teavm-core \
    -Dversion="$coordinate" -Dpackaging=jar

printf 'PASS PMLE-WASM2JS-TEAVM-FORK commit=%s coordinate=%s\n' \
  "$commit" "$coordinate"
