#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mocha_jar="$project/target/mochadoom-mle-simulation.jar"
presentation_mocha_jar="$project/target/mochadoom-mle-presentation.jar"
presentation_extra_patch="${DOOMDB_TEAVM_PRESENTATION_EXTRA_PATCH:-}"
presentation_candidate="${PMLE_PRESENTATION_CANDIDATE_BUILD:-NO}"
presentation_candidate_reason="${PMLE_PRESENTATION_CANDIDATE_REASON:-}"
candidate_patch_set_sha="none"
table_pack="$project/target/canonical-runtime-v2.bin"
iwad="$project/target/iwad-smoke/freedoom1.wad"
artifact="$project/target/javascript/doom-mle-presentation-engine-headless.js"
expected_input_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.presentation.inputBytecodeSha256)")"
expected_mocha_sha="${PMLE_PRESENTATION_MOCHA_SHA256:-$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.presentation.mochaBytecodeSha256)")}"
expected_output_bytes="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(String(v.teaVM.presentation.outputBytes))")"
expected_output_sha="$(node -e \
  "const fs=require('fs');const v=JSON.parse(fs.readFileSync('$root/versions.lock'));process.stdout.write(v.teaVM.presentation.outputSha256)")"
[[ "$presentation_candidate" == NO || "$presentation_candidate" == YES ]] || {
  printf 'PMLE_PRESENTATION_CANDIDATE_BUILD must be YES or NO\n' >&2
  exit 2
}
if [[ -n "$presentation_extra_patch" ]]; then
  IFS=',' read -r -a candidate_patches <<<"$presentation_extra_patch"
  for candidate_patch in "${candidate_patches[@]}"; do
    [[ -s "$candidate_patch" ]] || {
      printf 'presentation candidate patch missing: %s\n' "$candidate_patch" >&2
      exit 2
    }
  done
  [[ "$presentation_candidate" == YES ]] || {
    printf 'presentation extra patches require PMLE_PRESENTATION_CANDIDATE_BUILD=YES\n' >&2
    exit 2
  }
  candidate_patch_set_sha="$(
    for candidate_patch in "${candidate_patches[@]}"; do
      printf '%s  %s\n' \
        "$(shasum -a 256 "$candidate_patch" | awk '{print $1}')" \
        "$(basename "$candidate_patch")"
    done | shasum -a 256 | awk '{print $1}'
  )"
fi
if [[ "$presentation_candidate" == YES &&
      ! "$presentation_candidate_reason" =~ ^[a-z0-9][a-z0-9-]{2,63}$ ]]; then
  printf 'presentation source-only candidate requires a stable candidate reason\n' >&2
  exit 2
fi

for input in "$mocha_jar" "$table_pack" "$iwad"; do
  [[ -s "$input" ]] || { printf 'presentation prerequisite missing: %s\n' "$input" >&2;exit 2; }
done
actual_mocha_sha="$(shasum -a 256 "$mocha_jar" | awk '{print $1}')"
DOOMDB_MOCHA_EXPECTED_CLASS_COUNT=828 \
  DOOMDB_MOCHA_EXTRA_PATCH="$project/0002-teavm-simulation-headless.patch,$project/0003-teavm-presentation-compat.patch,$project/0004-teavm-authority-init-diet.patch,$project/0005-teavm-statusbar-compat.patch${presentation_extra_patch:+,$presentation_extra_patch}" \
  "$root/scripts/mochadoom/build-ojvm-jar.sh" \
  "$presentation_mocha_jar" \
  "$project/target/mochadoom-mle-presentation.json"
actual_mocha_sha="$(shasum -a 256 "$presentation_mocha_jar" | awk '{print $1}')"
if [[ "$presentation_candidate" == NO && "$actual_mocha_sha" != "$expected_mocha_sha" ]]; then
  printf 'presentation Mocha bytecode drift: %s (expected %s)\n' \
    "$actual_mocha_sha" "$expected_mocha_sha" >&2
  exit 1
fi

docker run --rm -v doomdb-maven-cache:/root/.m2 -v "$root:/work" \
  -w /work/probes/mle/teavm-engine maven:3.9.11-eclipse-temurin-17 \
  mvn -B -DskipTests -Ppresentation-engine-headless \
  -Dmochadoom.jar=/work/probes/mle/teavm-engine/target/mochadoom-mle-presentation.jar \
  package
test -s "$artifact"
input_jar="$project/target/mochadoom-mle-engine-slice-1.0.0.jar"
actual_input_sha="$(shasum -a 256 "$input_jar" | awk '{print $1}')"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
if [[ "$presentation_candidate" == NO &&
      ("$actual_input_sha" != "$expected_input_sha" ||
       "$artifact_bytes" != "$expected_output_bytes" ||
       "$artifact_sha" != "$expected_output_sha") ]]; then
  printf 'pinned presentation build drift: input=%s output=%s/%s expected=%s/%s/%s\n' \
    "$actual_input_sha" "$artifact_bytes" "$artifact_sha" \
    "$expected_input_sha" "$expected_output_bytes" "$expected_output_sha" >&2
  exit 1
fi

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
printf 'PASS PMLE-TEAVM-PRESENTATION-BUILD bytes=%s sha256=%s input_bytecode_sha256=%s mocha_bytecode_sha256=%s profile=presentation-engine-headless classification=%s candidate_reason=%s patch_set_sha256=%s\n' \
  "$artifact_bytes" "$artifact_sha" \
  "$actual_input_sha" "$actual_mocha_sha" \
  "$([[ "$presentation_candidate" == YES ]] && printf UNPROMOTED_CANDIDATE || printf PINNED)" \
  "$([[ "$presentation_candidate" == YES ]] && printf '%s' "${presentation_candidate_reason:-extra-patch}" || printf none)" \
  "$candidate_patch_set_sha"
