#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mocha_jar="$project/target/mochadoom-mle-simulation.jar"
presentation_mocha_jar="$project/target/mochadoom-mle-presentation.jar"
table_pack="$project/target/canonical-runtime-v2.bin"
iwad="$project/target/iwad-smoke/freedoom1.wad"
artifact="$project/target/javascript/doom-mle-presentation-engine-headless.js"
expected_mocha_sha="${PMLE_PRESENTATION_MOCHA_SHA256:-$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.presentation.mochaBytecodeSha256)")}"

for input in "$mocha_jar" "$table_pack" "$iwad"; do
  [[ -s "$input" ]] || { printf 'presentation prerequisite missing: %s\n' "$input" >&2;exit 2; }
done
actual_mocha_sha="$(shasum -a 256 "$mocha_jar" | awk '{print $1}')"
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
  DOOMDB_MOCHA_EXTRA_PATCH="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch,$project/0004-teavm-authority-init-diet.patch,$project/0005-teavm-statusbar-compat.patch" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$presentation_mocha_jar" \
  "$project/target/mochadoom-mle-presentation.json"
actual_mocha_sha="$(shasum -a 256 "$presentation_mocha_jar" | awk '{print $1}')"
[[ "$actual_mocha_sha" == "$expected_mocha_sha" ]] || {
  printf 'presentation Mocha bytecode drift: %s (expected %s)\n' \
    "$actual_mocha_sha" "$expected_mocha_sha" >&2
  exit 1
}

docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Ppresentation-engine-headless \
  -Dmochadoom.jar=/work/probes/mle/teavm-engine/target/mochadoom-mle-presentation.jar \
  package
test -s "$artifact"

mapfile -t emitted_math < <((rg -o 'Math\.[A-Za-z_$][A-Za-z0-9_$]*' \
  "$artifact" || true) | sort -u)
for math_member in "${emitted_math[@]}"; do
  case "$math_member" in
    Math.imul|Math.floor|Math.ceil|Math.round|Math.fround|Math.abs|Math.min|Math.max|Math.trunc|Math.sign)
      ;;
    *)
      printf 'presentation Math member is not allowlisted: %s\n' "$math_member" >&2
      exit 1
      ;;
  esac
done
if rg -F 'Math[' "$artifact" >/dev/null; then
  printf 'presentation computed Math member access is forbidden\n' >&2
  exit 1
fi

node "$project/run-presentation-node.mjs" "$iwad" "$table_pack"
input_jar="$project/target/mochadoom-mle-engine-slice-1.0.0.jar"
printf 'PASS PMLE-TEAVM-PRESENTATION-BUILD bytes=%s sha256=%s input_bytecode_sha256=%s mocha_bytecode_sha256=%s profile=presentation-engine-headless\n' \
  "$(wc -c <"$artifact" | tr -d '[:space:]')" \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "$(shasum -a 256 "$input_jar" | awk '{print $1}')" "$actual_mocha_sha"
