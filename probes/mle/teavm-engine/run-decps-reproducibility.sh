#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-decps-rank"
candidate="${PMLE_CANDIDATE_FILE:-$evidence/authority-candidate-5ec18cbe4cff.js}"
patch="$project/0006-teavm-authority-no-blocking-wait.patch"
extractor="$project/extract-build-sha.mjs"
expected_sha="${PMLE_EXPECTED_AUTHORITY_SHA256:-5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3}"
expected_bytes="${PMLE_EXPECTED_AUTHORITY_BYTES:-1081335}"
log="${PMLE_REPRODUCIBILITY_LOG:-$evidence/rebuild-5ec18cbe4cff.log}"
attest_existing="${PMLE_REPRODUCIBILITY_ATTEST_EXISTING:-NO}"

if [[ "$attest_existing" == YES ]]; then
  [[ -s "$log" ]] || {
    printf 'de-CPS reproducibility evidence is missing: %s\n' "$log" >&2
    exit 1
  }
else
  [[ "$attest_existing" == NO ]] || {
    printf 'invalid PMLE_REPRODUCIBILITY_ATTEST_EXISTING value: %s\n' \
      "$attest_existing" >&2
    exit 2
  }
  [[ ! -e "$log" ]] || {
    printf 'de-CPS reproducibility evidence exists: %s\n' "$log" >&2
    exit 1
  }
fi
for input in "$candidate" "$patch" "$extractor"; do
  [[ -s "$input" ]] || {
    printf 'de-CPS reproducibility input missing: %s\n' "$input" >&2
    exit 2
  }
done
[[ "$(wc -c <"$candidate" | tr -d '[:space:]')" == "$expected_bytes" ]]
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$expected_sha" ]]
node "$extractor" --self-test

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[r]un-worker-soak|[r]un-live-command-matrix-mle|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'de-CPS reproducibility build refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'de-CPS reproducibility build requires a quiet host:\n%s\n' \
    "$busy_host" >&2
  exit 1
}

mkdir -p "$evidence"
if [[ "$attest_existing" == NO ]]; then
  PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
  PMLE_AUTHORITY_CANDIDATE_REASON=decps-promotion-rebuild \
  DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch" \
    "$project/build-simulation.sh" | tee "$log"
fi

rebuilt="$project/target/javascript/doom-mle-simulation-engine-headless.js"
[[ -s "$rebuilt" ]]
actual_bytes="$(wc -c <"$rebuilt" | tr -d '[:space:]')"
actual_sha="$(shasum -a 256 "$rebuilt" | awk '{print $1}')"
[[ "$actual_bytes" == "$expected_bytes" && "$actual_sha" == "$expected_sha" ]] || {
  printf 'de-CPS rebuild drift: bytes=%s sha256=%s expected=%s/%s\n' \
    "$actual_bytes" "$actual_sha" "$expected_bytes" "$expected_sha" >&2
  exit 1
}
cmp -s "$candidate" "$rebuilt" || {
  printf '%s\n' 'de-CPS rebuild is not byte-identical to promotion candidate' >&2
  exit 1
}

marker='PASS PMLE-TEAVM-SIMULATION-BUILD'
input_sha="$(node "$extractor" "$log" "$marker" input_bytecode_sha256)"
mocha_sha="$(node "$extractor" "$log" "$marker" mocha_bytecode_sha256)"
classification="$(
  node "$extractor" "$log" "$marker" classification token
)"
reason="$(node "$extractor" "$log" "$marker" candidate_reason token)"
patch_set_sha="$(node "$extractor" "$log" "$marker" patch_set_sha256)"
expected_patch_set_sha="$(
  printf '%s  %s\n' \
    "$(shasum -a 256 "$patch" | awk '{print $1}')" "$(basename "$patch")" |
    shasum -a 256 | awk '{print $1}'
)"
[[ "$input_sha" =~ ^[0-9a-f]{64}$ && "$mocha_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$classification" == UNPROMOTED_CANDIDATE ]]
[[ "$reason" == decps-promotion-rebuild ]]
[[ "$patch_set_sha" == "$expected_patch_set_sha" ]]
[[ "$(grep -c '^PMLE_DECPS_REPRODUCIBILITY|' "$log" || true)" == 0 ]] || {
  printf '%s\n' 'de-CPS reproducibility terminal marker already exists' >&2
  exit 1
}

if [[ "$attest_existing" == YES ]]; then
  printf '%s\n' \
    'PMLE_DECPS_REPRODUCIBILITY_VERIFIER_RECOVERY|ATTEST_EXISTING|reason=metadata_extractor_token_mode_fixed' |
    tee -a "$log"
fi
printf 'PMLE_DECPS_REPRODUCIBILITY|PASS|bytes=%s|sha256=%s|input_bytecode_sha256=%s|mocha_bytecode_sha256=%s|patch_set_sha256=%s\n' \
  "$actual_bytes" "$actual_sha" "$input_sha" "$mocha_sha" "$patch_set_sha" |
  tee -a "$log"
