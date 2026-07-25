#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
table_pack="$project/target/canonical-runtime-v2.bin"
table_pack_sha256="058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44"
optimization_level="${DOOMDB_TEAVM_OPTIMIZATION_LEVEL:-ADVANCED}"
minifying="${DOOMDB_TEAVM_MINIFYING:-true}"
authority_extra_patch="${DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH:-}"
authority_candidate="${PMLE_AUTHORITY_CANDIDATE_BUILD:-NO}"
authority_candidate_reason="${PMLE_AUTHORITY_CANDIDATE_REASON:-}"
candidate_patch_set_sha="none"
pinned_authority_patch_set=NO
expected_input_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.inputBytecodeSha256)")"
expected_mocha_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.mochaBytecodeSha256)")"
expected_output_bytes="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(String(v.teaVM.outputBytes))")"
expected_output_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.outputSha256)")"
if [[ -z "$authority_extra_patch" && "$authority_candidate" == NO ]]; then
  authority_extra_patch="$(node -e \
    "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write((v.teaVM.authorityExtraPatches??[]).map(p=>'$root/'+p).join(','))")"
  [[ -z "$authority_extra_patch" ]] || pinned_authority_patch_set=YES
fi
[[ "$optimization_level" == ADVANCED || "$optimization_level" == FULL ||
    "$optimization_level" == SIMPLE ]] || {
  printf 'DOOMDB_TEAVM_OPTIMIZATION_LEVEL must be SIMPLE, ADVANCED, or FULL\n' >&2
  exit 2
}
[[ "$minifying" == true || "$minifying" == false ]] || {
  printf 'DOOMDB_TEAVM_MINIFYING must be true or false\n' >&2
  exit 2
}
[[ "$authority_candidate" == NO || "$authority_candidate" == YES ]] || {
  printf 'PMLE_AUTHORITY_CANDIDATE_BUILD must be YES or NO\n' >&2
  exit 2
}
if [[ -n "$authority_extra_patch" ]]; then
  IFS=',' read -r -a candidate_patches <<<"$authority_extra_patch"
  for candidate_patch in "${candidate_patches[@]}"; do
    [[ -s "$candidate_patch" ]] || {
      printf 'authority candidate patch missing: %s\n' "$candidate_patch" >&2
      exit 2
    }
  done
  [[ "$authority_candidate" == YES || "$pinned_authority_patch_set" == YES ]] || {
    printf 'authority extra patches require PMLE_AUTHORITY_CANDIDATE_BUILD=YES\n' >&2
    exit 2
  }
  candidate_patch_set_sha="$(
    for candidate_patch in "${candidate_patches[@]}"; do
      printf '%s  %s\n' \
        "$(shasum -a 256 "$candidate_patch" | awk '{print $1}')" \
        "$(basename "$candidate_patch")"
    done | shasum -a 256 | awk '{print $1}'
  )"
  if [[ "$pinned_authority_patch_set" == YES ]]; then
    expected_patch_set_sha="$(node -e \
      "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.authorityExtraPatchSetSha256??'')")"
    [[ "$candidate_patch_set_sha" == "$expected_patch_set_sha" ]] || {
      printf 'pinned authority patch-set drift: actual=%s expected=%s\n' \
        "$candidate_patch_set_sha" "$expected_patch_set_sha" >&2
      exit 1
    }
  fi
fi
if [[ "$authority_candidate" == YES &&
      ! "$authority_candidate_reason" =~ ^[a-z0-9][a-z0-9-]{2,63}$ ]]; then
  printf 'authority candidate requires a stable candidate reason\n' >&2
  exit 2
fi
if [[ "$optimization_level" == SIMPLE &&
      ! ( "$authority_candidate" == YES &&
          "$authority_candidate_reason" == jit-digestibility-simple ) ]]; then
  printf '%s\n' \
    'SIMPLE is restricted to the unpromotable JIT-digestibility diagnostic' >&2
  exit 2
fi
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
  DOOMDB_MOCHA_EXTRA_PATCH="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch,$project/0004-teavm-authority-init-diet.patch${authority_extra_patch:+,$authority_extra_patch}" \
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
docker cp "$project/src/build/java/doomdb/mle/engine/FixedDivPropertyTest.java" \
  "$container:$remote/FixedDivPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/CanonicalTranmapPropertyTest.java" \
  "$container:$remote/CanonicalTranmapPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/DeterministicSqrtPropertyTest.java" \
  "$container:$remote/DeterministicSqrtPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/IterativeBspTraversalPropertyTest.java" \
  "$container:$remote/IterativeBspTraversalPropertyTest.java" >/dev/null
docker cp "$project/src/build/java/doomdb/mle/engine/LongFlagLowWordPropertyTest.java" \
  "$container:$remote/LongFlagLowWordPropertyTest.java" >/dev/null
docker exec -u 0 "$container" chmod 644 \
  "$remote/mochadoom-canonical-table-source.jar" \
  "$remote/mochadoom-mle-simulation.jar" \
  "$remote/CanonicalTablePackGenerator.java" "$remote/FixedMulPropertyTest.java" \
  "$remote/FixedDivPropertyTest.java" \
  "$remote/CanonicalTranmapPropertyTest.java"
docker exec -u 0 "$container" chmod 644 "$remote/DeterministicSqrtPropertyTest.java"
docker exec -u 0 "$container" chmod 644 \
  "$remote/IterativeBspTraversalPropertyTest.java" \
  "$remote/LongFlagLowWordPropertyTest.java"
docker exec "$container" "$java_home/jdk/bin/javac" --release 8 \
  -cp "$remote/mochadoom-canonical-table-source.jar" \
  -d "$remote/classes" \
  "$remote/CanonicalTablePackGenerator.java" "$remote/FixedMulPropertyTest.java" \
  "$remote/FixedDivPropertyTest.java" \
  "$remote/CanonicalTranmapPropertyTest.java" \
  "$remote/IterativeBspTraversalPropertyTest.java" \
  "$remote/LongFlagLowWordPropertyTest.java"
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
fixed_div_property_output="$(docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-mle-simulation.jar" \
  doomdb.mle.engine.FixedDivPropertyTest)"
printf '%s\n' "$fixed_div_property_output"
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes:$remote/mochadoom-mle-simulation.jar" \
  doomdb.mle.engine.DeterministicSqrtPropertyTest \
  "$remote/freedoom1.wad" "$remote/canonical-runtime-v2.bin"
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes" \
  doomdb.mle.engine.IterativeBspTraversalPropertyTest
docker exec "$container" "$java_home/jdk/bin/java" \
  -cp "$remote/classes" \
  doomdb.mle.engine.LongFlagLowWordPropertyTest
fixed_mul_checksum="$(printf '%s\n' "$fixed_mul_property_output" \
  | awk -F'checksum=' '/^PASS FIXED_MUL_PROPERTY / {print $2}')"
fixed_div_checksum="$(printf '%s\n' "$fixed_div_property_output" \
  | awk -F'checksum=' '/^PASS FIXED_DIV_PROPERTY / {print $2}')"
[[ "$fixed_mul_checksum" =~ ^-?[0-9]+$ ]] || {
  printf 'invalid FixedMul property checksum: %s\n' "$fixed_mul_checksum" >&2
  exit 1
}
[[ "$fixed_div_checksum" =~ ^-?[0-9]+$ ]] || {
  printf 'invalid FixedDiv property checksum: %s\n' "$fixed_div_checksum" >&2
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
  mvn -B -DskipTests "-Dteavm.optimizationLevel=$optimization_level" \
  "-Dteavm.minifying=$minifying" \
  -Psimulation-engine-headless package
test -s "$project/target/javascript/doom-mle-simulation-engine-headless.js"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
input_jar="$project/target/mochadoom-mle-engine-slice-1.0.0.jar"
actual_input_sha="$(shasum -a 256 "$input_jar" | awk '{print $1}')"
actual_mocha_sha="$(
  shasum -a 256 "$project/target/mochadoom-mle-simulation.jar" | awk '{print $1}'
)"
actual_output_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
actual_output_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
if [[ "$authority_candidate" == NO &&
      ("$actual_input_sha" != "$expected_input_sha" ||
       "$actual_mocha_sha" != "$expected_mocha_sha" ||
       "$actual_output_bytes" != "$expected_output_bytes" ||
       "$actual_output_sha" != "$expected_output_sha") ]]; then
  printf 'pinned authority build drift: input=%s mocha=%s output=%s/%s expected=%s/%s/%s/%s\n' \
    "$actual_input_sha" "$actual_mocha_sha" \
    "$actual_output_bytes" "$actual_output_sha" \
    "$expected_input_sha" "$expected_mocha_sha" \
    "$expected_output_bytes" "$expected_output_sha" >&2
  exit 1
fi
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
  "$fixed_mul_checksum" "$fixed_div_checksum"
printf 'PASS PMLE-TEAVM-SIMULATION-BUILD optimization_level=%s minifying=%s bytes=%s sha256=%s input_bytecode_sha256=%s mocha_bytecode_sha256=%s table_pack_bytes=%s table_pack_sha256=%s fixed_mul_checksum=%s fixed_div_checksum=%s runtime_math_allowlist=%s classification=%s candidate_reason=%s patch_set_sha256=%s\n' \
  "$optimization_level" "$minifying" "$actual_output_bytes" "$actual_output_sha" \
  "$actual_input_sha" "$actual_mocha_sha" \
  "$(wc -c <"$table_pack" | tr -d '[:space:]')" "$actual_table_pack_sha256" \
  "$fixed_mul_checksum" "$fixed_div_checksum" "$math_allowlist" \
  "$([[ "$authority_candidate" == YES ]] && printf UNPROMOTED_CANDIDATE || printf PINNED)" \
  "$([[ "$authority_candidate" == YES ]] && printf '%s' "$authority_candidate_reason" || printf none)" \
  "$candidate_patch_set_sha"
