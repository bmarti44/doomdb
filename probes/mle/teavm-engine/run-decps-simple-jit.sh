#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-hidden-jit"
profile_log="$root/artifacts/performance/pmle-decps-rank/node-decps-peak-5ec18cbe4cff-v3.log"
profile="$root/artifacts/performance/pmle-decps-rank/node-decps-peak-5ec18cbe4cff-v3.cpuprofile"
profile_validator="$project/validate-decps-node-profile.mjs"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
patch="$project/0006-teavm-authority-no-blocking-wait.patch"
pinned="$root/client/dist/play/doom-mle-authority-5ec18cbe4cff.js"
landing="$root/artifacts/performance/pmle-decps-rank/default-async-pair-5ec18cbe4cff-5250-final-artifact-repro-2026-07-25-comparison.log"
saved="$(mktemp "${TMPDIR:-/tmp}/doomdb-simple-jit-authority.XXXXXX")"
build_log="$evidence/simple-jit-build-5ec18cbe-2026-07-25.log"
parity_log="$evidence/simple-jit-parity-5ec18cbe-2026-07-25.log"
verdict_log="$evidence/simple-jit-verdict-5ec18cbe-2026-07-25.log"

restore() {
  local status=$?
  trap - EXIT
  if [[ -s "$saved" ]]; then cp "$saved" "$artifact" || status=1; fi
  rm -f "$saved"
  exit "$status"
}
trap restore EXIT

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-decps-rank-mle/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'SIMPLE JIT diagnostic refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
[[ "${PMLE_HIDDEN_JIT_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_HIDDEN_JIT_EXECUTE=YES for the SIMPLE JIT diagnostic' >&2
  exit 2
}
node "$profile_validator" --self-test
if ! node "$profile_validator" "$profile_log" "$profile"; then
  printf '%s\n' 'fresh de-CPS Node profile must precede SIMPLE JIT work' >&2
  exit 1
fi
grep -Fq \
  'PMLE_DECPS_ASYNC_JIT|PASS|passes=2|tics_per_pass=5250|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' \
  "$landing"
grep -Fq '|verdict=LANDING_SIGNAL' "$landing"
[[ "$(shasum -a 256 "$pinned" | awk '{print $1}')" == \
  5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3 ]]
for output in "$build_log" "$parity_log" "$verdict_log"; do
  [[ ! -e "$output" ]] || {
    printf 'SIMPLE JIT evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
test -s "$artifact"
cp "$artifact" "$saved"
mkdir -p "$evidence"

PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
PMLE_AUTHORITY_CANDIDATE_REASON=jit-digestibility-simple \
DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch" \
DOOMDB_TEAVM_OPTIMIZATION_LEVEL=SIMPLE \
  "$project/build-simulation.sh" | tee "$build_log"
grep -Eq \
  '^PASS PMLE-TEAVM-SIMULATION-BUILD optimization_level=SIMPLE .*classification=UNPROMOTED_CANDIDATE candidate_reason=jit-digestibility-simple ' \
  "$build_log"
simple_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
simple_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"

DOOMDB_MLE_CANDIDATE="$artifact" \
DOOMDB_MLE_ORACLE="$pinned" \
  node "$project/run-javascript-candidate-parity.mjs" | tee "$parity_log"
grep -Fq \
  " candidate_sha256=$simple_sha oracle_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3" \
  "$parity_log"

set +e
DOOMDB_DECPS_CANDIDATE="$artifact" \
DOOMDB_DECPS_EXPECTED_SHA="$simple_sha" \
PMLE_HIDDEN_JIT_EXECUTE=YES \
  "$project/run-decps-rank-mle.sh" simple-jit 500
rank_status=$?
set -e
if [[ "$rank_status" == 0 ]]; then
  verdict=SIGNAL_TARGETED_NOINLINE_CENSUS_ALLOWED
elif [[ "$rank_status" == 124 ]]; then
  verdict=PARK_NO_TARGETED_NOINLINE_WORK
else
  printf 'SIMPLE JIT rank failed outside the 60-minute park timeout: %s\n' \
    "$rank_status" >&2
  exit "$rank_status"
fi
printf 'PMLE_DECPS_SIMPLE_JIT|DIAGNOSTIC_NOT_GATE|verdict=%s|sha256=%s|bytes=%s|rank_exit=%s|profile=%s\n' \
  "$verdict" "$simple_sha" "$simple_bytes" "$rank_status" \
  "${profile_log#"$root"/}" | tee "$verdict_log"
