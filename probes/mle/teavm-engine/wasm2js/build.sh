#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
spike="$project/wasm2js"
tool_container="doomdb-wasm2js-javac-$$"
patches="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch,$project/0004-teavm-authority-init-diet.patch,$project/0006-teavm-authority-no-blocking-wait.patch,$spike/0001-legacy-wasm-runtime-cpu.patch,$spike/0002-legacy-wasm-level-loader-ssa.patch"
adapter_patch="${DOOMDB_WASM2JS_ADAPTER_PATCH:-}"
adapter_patch_sha=none
if [[ -n "$adapter_patch" ]]; then
  [[ -s "$adapter_patch" ]] || {
    printf 'wasm2js adapter patch missing: %s\n' "$adapter_patch" >&2
    exit 2
  }
  adapter_patch_sha="$(shasum -a 256 "$adapter_patch" | awk '{print $1}')"
fi

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-differential[.]sh|[r]un-worker-cutover|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'wasm2js build refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'wasm2js build requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}

cleanup() {
  docker rm -f "$tool_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Build an isolated Mocha JAR from the production authority patches, including
# the accepted de-CPS change. The two final patches are legacy-Wasm-only
# compatibility changes: one removes an unreachable renderer CPU query and the
# other repairs a TeaVM 0.13 SSA issue in the level loader.
docker run -d --rm --name "$tool_container" \
  maven:3.9.11-eclipse-temurin-17 sleep 1800 >/dev/null
docker exec -u 0 "$tool_container" \
  ln -s /opt/java/openjdk /opt/java/openjdk/jdk
DOOMDB_JAVA_TOOL_CONTAINER="$tool_container" \
DOOMDB_JAVA_TOOL_HOME=/opt/java/openjdk \
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
DOOMDB_MOCHA_EXTRA_PATCH="$patches" \
DOOMDB_MOCHA_EXTRA_ADAPTER_PATCH="$adapter_patch" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$spike/target/mochadoom-wasm2js-simulation.jar" \
  "$spike/target/mochadoom-wasm2js-simulation.json"

"$spike/build-teavm-singlethread.sh"

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

patch_set_sha="$(
  IFS=',' read -r -a patch_paths <<<"$patches"
  for patch_path in "${patch_paths[@]}"; do
    printf '%s  %s\n' \
      "$(shasum -a 256 "$patch_path" | awk '{print $1}')" \
      "$(basename "$patch_path")"
  done | shasum -a 256 | awk '{print $1}'
)"
printf 'PASS PMLE-WASM2JS-TEAVM-BUILD teavm=0.13.1 wasm_bytes=%s wasm_sha256=%s runtime_bytes=%s runtime_sha256=%s mocha_jar_sha256=%s patch_set_sha256=%s adapter_patch_sha256=%s decps=YES\n' \
  "$(wc -c <"$wasm" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$wasm" | awk '{print $1}')" \
  "$(wc -c <"$runtime" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$runtime" | awk '{print $1}')" \
  "$(shasum -a 256 "$spike/target/mochadoom-wasm2js-simulation.jar" | awk '{print $1}')" \
  "$patch_set_sha" "$adapter_patch_sha"
