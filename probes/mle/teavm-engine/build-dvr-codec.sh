#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
artifact="$project/target/javascript/doom-mle-dvr-frame-codec.js"
codec_source="$project/src/dvr/java/doomdb/mle/engine/DvrFrameCodec.java"
property_source="$project/src/build/java/doomdb/mle/engine/DvrFrameCodecPropertyTest.java"

for input in "$codec_source" "$property_source" "$project/pom.xml" \
    "$project/target/mochadoom-mle-simulation.jar"; do
  [[ -s "$input" ]] || {
    printf 'DVR codec prerequisite is absent: %s\n' "$input" >&2
    exit 2
  }
done

rm -rf "$project/target/dvr-codec-property"
mkdir -p "$project/target/dvr-codec-property"
docker run --rm -v "$root:/work" -w /work \
  eclipse-temurin:17-jdk \
  javac --release 11 -d probes/mle/teavm-engine/target/dvr-codec-property \
    probes/mle/teavm-engine/src/dvr/java/doomdb/mle/engine/DvrFrameCodec.java \
    probes/mle/teavm-engine/src/build/java/doomdb/mle/engine/DvrFrameCodecPropertyTest.java
docker run --rm -v "$root:/work" -w /work \
  eclipse-temurin:17-jdk \
  java -cp probes/mle/teavm-engine/target/dvr-codec-property \
    doomdb.mle.engine.DvrFrameCodecPropertyTest

docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Pdvr-frame-codec \
    -Dmochadoom.jar=/work/probes/mle/teavm-engine/target/mochadoom-mle-simulation.jar \
    package

test -s "$artifact"
bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
source_sha256="$(
  {
    shasum -a 256 \
      "$project/src/dvr/java/doomdb/mle/engine/DvrFrameCodec.java"
    shasum -a 256 \
      "$project/src/dvr/java/doomdb/mle/engine/DvrFrameCodecReachabilityProbe.java"
  } | shasum -a 256 | awk '{print $1}'
)"
printf 'PASS PMLE-DVR-CODEC-BUILD codec=DOOM_DFR1_RLE version=1 bytes=%s sha256=%s source_set_sha256=%s classification=UNPROMOTED_CANDIDATE\n' \
  "$bytes" "$sha256" "$source_sha256"
