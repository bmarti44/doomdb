#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
table_pack="$project/target/canonical-runtime-v2.bin"
table_pack_sha256="058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"
container="${DOOMDB_JAVA_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_JAVA_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
remote="/tmp/doomdb-mle-table-pack-$$"
mkdir -p "$project/target/iwad-smoke"
# Maven does not notice changed classes inside the system-scoped pinned JAR.
# Remove only its derived compilation outputs before rebuilding; retain the two
# source JARs generated below in target for the subsequent TeaVM invocation.
rm -rf "$project/target/classes" "$project/target/generated-sources" \
  "$project/target/javascript" "$project/target/maven-archiver" \
  "$project/target/maven-status"
rm -f "$project/target/mochadoom-mle-engine-slice-"*.jar
unzip -jo "$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip" \
  freedoom-0.13.0/freedoom1.wad -d "$project/target/iwad-smoke"
[[ -n "$container" ]] || { printf 'pinned Oracle JVM container is unavailable\n' >&2; exit 2; }
cleanup(){ docker exec -u 0 "$container" rm -rf "$remote" >/dev/null 2>&1 || true; }
trap cleanup EXIT
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=830 \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$project/target/mochadoom-canonical-table-source.jar" \
  "$project/target/mochadoom-canonical-table-source.json"
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
  DOOMDB_MOCHA_EXTRA_PATCH="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$project/target/mochadoom-mle-simulation.jar" \
  "$project/target/mochadoom-mle-simulation.json"
docker exec "$container" mkdir -p "$remote/classes"
docker cp "$project/target/mochadoom-canonical-table-source.jar" \
  "$container:$remote/mochadoom-canonical-table-source.jar" >/dev/null
docker cp "$project/target/mochadoom-mle-simulation.jar" \
  "$container:$remote/mochadoom-mle-simulation.jar" >/dev/null
docker cp "$project/target/iwad-smoke/freedoom1.wad" \
  "$container:$remote/freedoom1.wad" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/CanonicalTablePackGenerator.java" \
  "$container:$remote/CanonicalTablePackGenerator.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/FixedMulPropertyTest.java" \
  "$container:$remote/FixedMulPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/CanonicalTranmapPropertyTest.java" \
  "$container:$remote/CanonicalTranmapPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/DeterministicSqrtPropertyTest.java" \
  "$container:$remote/DeterministicSqrtPropertyTest.java" >/dev/null
docker exec -u 0 "$container" chmod 644 \
  "$remote/mochadoom-canonical-table-source.jar" \
  "$remote/mochadoom-mle-simulation.jar" \
  "$remote/CanonicalTablePackGenerator.java" "$remote/FixedMulPropertyTest.java" \
  "$remote/CanonicalTranmapPropertyTest.java"
docker exec -u 0 "$container" chmod 644 "$remote/DeterministicSqrtPropertyTest.java"
docker exec "$container" "$java_home/jdk/bin/javac" --release 8 \
  -cp "$remote/mochadoom-canonical-table-source.jar" \
  -d "$remote/classes" \
  "$remote/CanonicalTablePackGenerator.java" "$remote/FixedMulPropertyTest.java" \
  "$remote/CanonicalTranmapPropertyTest.java"
docker exec "$container" "$java_home/jdk/bin/javac" --release 8 \
  -cp "$remote/mochadoom-mle-simulation.jar:$remote/classes" -d "$remote/classes" \
  "$remote/DeterministicSqrtPropertyTest.java"
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-canonical-table-source.jar" \
  doomdb.mle.engine.CanonicalTablePackGenerator \
  "$remote/freedoom1.wad" "$remote/canonical-runtime-v2.bin"
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-canonical-table-source.jar" \
  doomdb.mle.engine.CanonicalTranmapPropertyTest \
  "$remote/freedoom1.wad" "$remote/canonical-runtime-v2.bin"
docker cp "$container:$remote/canonical-runtime-v2.bin" "$table_pack" >/dev/null
fixed_mul_property_output="$(docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-mle-simulation.jar" \
  doomdb.mle.engine.FixedMulPropertyTest)"
printf '%s\n' "$fixed_mul_property_output"
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-mle-simulation.jar" \
  doomdb.mle.engine.DeterministicSqrtPropertyTest \
  "$remote/freedoom1.wad" "$remote/canonical-runtime-v2.bin"
fixed_mul_checksum="$(printf '%s\n' "$fixed_mul_property_output" \
  | awk -F'checksum=' '/^PASS FIXED_MUL_PROPERTY / {print $2}')"
[[ "$fixed_mul_checksum" =~ ^-?[0-9]+$ ]] || {
  printf 'invalid FixedMul property checksum: %s\n' "$fixed_mul_checksum" >&2
  exit 1
}
actual_table_pack_sha256="$(shasum -a 256 "$table_pack" | awk '{print $1}')"
[[ "$actual_table_pack_sha256" == "$table_pack_sha256" ]] || {
  printf 'canonical table pack SHA-256 drift: %s (expected %s)\n' \
    "$actual_table_pack_sha256" "$table_pack_sha256" >&2
  exit 1
}
docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Psimulation-engine-headless package
test -s "$project/target/javascript/doom-mle-simulation-engine-headless.js"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
mapfile -t emitted_math < <((rg -o 'Math\.[A-Za-z_$][A-Za-z0-9_$]*' "$artifact" || true) | sort -u)
for math_member in "${emitted_math[@]}"; do
  case "$math_member" in
    Math.imul|Math.floor|Math.ceil|Math.round|Math.fround|Math.abs|Math.min|Math.max|Math.trunc|Math.sign)
      ;;
    *)
      printf 'emitted Math member is not allowlisted: %s\n' "$math_member" >&2
      exit 1
      ;;
  esac
done
if rg -F 'Math[' "$artifact" >/dev/null; then
  printf 'computed Math member access is forbidden\n' >&2
  exit 1
fi
math_allowlist="$(IFS=,; printf '%s' "${emitted_math[*]}")"
node "$project/run-simulation-node.mjs" \
  "$project/target/iwad-smoke/freedoom1.wad" "$table_pack" \
  "$fixed_mul_checksum"
printf 'PASS PMLE-TEAVM-SIMULATION-BUILD bytes=%s table_pack_bytes=%s table_pack_sha256=%s fixed_mul_checksum=%s runtime_math_allowlist=%s\n' \
  "$(wc -c <"$project/target/javascript/doom-mle-simulation-engine-headless.js" | tr -d '[:space:]')" \
  "$(wc -c <"$table_pack" | tr -d '[:space:]')" "$actual_table_pack_sha256" \
  "$fixed_mul_checksum" "$math_allowlist"
