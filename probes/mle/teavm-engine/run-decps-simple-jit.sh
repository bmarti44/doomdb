#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-hidden-jit"
profile_log="$root/artifacts/performance/pmle-decps-rank/node-decps-peak-2848ef7a8dc4.log"
profile="$root/artifacts/performance/pmle-decps-rank/node-decps-peak-2848ef7a8dc4.cpuprofile"
profile_validator="$project/validate-decps-node-profile.mjs"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
patch="$project/0006-teavm-authority-no-blocking-wait.patch"
saved="$(mktemp "${TMPDIR:-/tmp}/doomdb-simple-jit-authority.XXXXXX")"
build_log="$evidence/simple-jit-build-2026-07-24.log"
parity_log="$evidence/simple-jit-parity-2026-07-24.log"
verdict_log="$evidence/simple-jit-verdict-2026-07-24.log"

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
  node "$project/run-javascript-candidate-parity.mjs" | tee "$parity_log"
grep -Fq \
  " candidate_sha256=$simple_sha oracle_sha256=e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b" \
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
