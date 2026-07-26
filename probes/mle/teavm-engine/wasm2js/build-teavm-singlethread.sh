#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
spike="$root/probes/mle/teavm-engine/wasm2js"
source_dir="$spike/target/teavm-singlethread/source"
commit='b3a245b7d9034ff35cdfab2def057a3d4f256efb'
coordinate='0.13.1-doomdb-singlethread'
expected_jar_sha='c81017dfb2787f0ecc7cebf155a771ae92190d1b92bcaeba31721ac3fb080cad'

# The pinned fork is already installed in the project Maven volume from its
# accepted reproducible build. Reuse it only after an exact byte check. This
# also avoids depending on TeaVM's later Gradle conversion when a detached
# source checkout is refreshed solely to consume the already-proven fork.
cached_jar="/root/.m2/repository/org/teavm/teavm-core/$coordinate/teavm-core-$coordinate.jar"
if docker run --rm -v doomdb-maven-cache:/root/.m2 alpine sh -lc \
    "test -s '$cached_jar' && test \"\$(sha256sum '$cached_jar' | awk '{print \$1}')\" = '$expected_jar_sha'"; then
  printf 'PASS PMLE-WASM2JS-TEAVM-FORK commit=%s coordinate=%s jar_sha256=%s source=PINNED_MAVEN_CACHE\n' \
    "$commit" "$coordinate" "$expected_jar_sha"
  exit 0
fi

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
