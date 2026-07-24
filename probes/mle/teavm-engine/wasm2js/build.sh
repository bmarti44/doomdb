#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
spike="$project/wasm2js"
tool_container="doomdb-wasm2js-javac-$$"

cleanup() {
  docker rm -f "$tool_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Build an isolated Mocha JAR. The first three patches are the exact authority
# source inputs; the final patch only replaces an unreachable renderer default
# whose JDK query is unsupported by TeaVM's legacy WebAssembly class library.
docker run -d --rm --name "$tool_container" \
  maven:3.9.11-eclipse-temurin-17 sleep 1800 >/dev/null
docker exec -u 0 "$tool_container" \
  ln -s /opt/java/openjdk /opt/java/openjdk/jdk
DOOMDB_JAVA_TOOL_CONTAINER="$tool_container" \
DOOMDB_JAVA_TOOL_HOME=/opt/java/openjdk \
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
DOOMDB_MOCHA_EXTRA_PATCH="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch,$project/0004-teavm-authority-init-diet.patch,$spike/0001-legacy-wasm-runtime-cpu.patch" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$spike/target/mochadoom-wasm2js-simulation.jar" \
  "$spike/target/mochadoom-wasm2js-simulation.json"

docker run --rm \
  -v doomdb-maven-cache:/root/.m2 \
  -v "$root:/work" \
  -w /work/probes/mle/teavm-engine/wasm2js \
  maven:3.9.11-eclipse-temurin-17 \
  mvn -B -ntp package

wasm="$spike/target/wasm/doom-wasm2js-authority.wasm"
runtime="$spike/target/wasm/doom-wasm2js-authority.wasm-runtime.js"
test -s "$wasm"
test -s "$runtime"

printf 'PASS PMLE-WASM2JS-TEAVM-BUILD teavm=0.13.1 wasm_bytes=%s wasm_sha256=%s runtime_bytes=%s runtime_sha256=%s mocha_jar_sha256=%s\n' \
  "$(wc -c <"$wasm" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$wasm" | awk '{print $1}')" \
  "$(wc -c <"$runtime" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$runtime" | awk '{print $1}')" \
  "$(shasum -a 256 "$spike/target/mochadoom-wasm2js-simulation.jar" | awk '{print $1}')"
