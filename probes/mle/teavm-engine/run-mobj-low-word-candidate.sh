#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-decps-rank"
target="$project/target/javascript/doom-mle-simulation-engine-headless.js"
pinned="$root/client/dist/play/doom-mle-authority-5ec18cbe4cff.js"
patch_decps="$project/0006-teavm-authority-no-blocking-wait.patch"
patch_flags="$project/0008-teavm-authority-mobj-low-word.patch"
candidate="$evidence/authority-mobj-low-word-candidate.js"
build_log="$evidence/mobj-low-word-build-2026-07-25.log"
parity_log="$evidence/mobj-low-word-node-parity-2026-07-25.log"
saved="$(mktemp "${TMPDIR:-/tmp}/doomdb-mobj-low-word-target.XXXXXX")"
pinned_sha=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3

restore() {
  local status=$?
  trap - EXIT
  if [[ -s "$saved" ]]; then
    cp "$saved" "$target" || status=1
  fi
  rm -f "$saved"
  exit "$status"
}
trap restore EXIT

for output in "$candidate" "$build_log" "$parity_log"; do
  [[ ! -e "$output" ]] ||
    { printf 'mobj low-word evidence exists: %s\n' "$output" >&2; exit 1; }
done
for input in "$target" "$pinned" "$patch_decps" "$patch_flags"; do
  [[ -s "$input" ]] ||
    { printf 'mobj low-word input missing: %s\n' "$input" >&2; exit 2; }
done
[[ "$(shasum -a 256 "$target" | awk '{print $1}')" == "$pinned_sha" ]]
[[ "$(shasum -a 256 "$pinned" | awk '{print $1}')" == "$pinned_sha" ]]
git -C "$root/third_party/mochadoom" apply --check \
  "../../probes/mle/teavm-engine/0008-teavm-authority-mobj-low-word.patch"
cp "$target" "$saved"

PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
PMLE_AUTHORITY_CANDIDATE_REASON=mobj-low-word \
DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch_decps,$patch_flags" \
  "$project/build-simulation.sh" | tee "$build_log"
grep -q '^PASS LONG_FLAG_LOW_WORD_PROPERTY ' "$build_log"
grep -Eq '^PASS PMLE-TEAVM-SIMULATION-BUILD .*classification=UNPROMOTED_CANDIDATE candidate_reason=mobj-low-word ' \
  "$build_log"
cp "$target" "$candidate"
candidate_sha="$(shasum -a 256 "$candidate" | awk '{print $1}')"
candidate_bytes="$(wc -c <"$candidate" | tr -d '[:space:]')"
printf 'PMLE_MOBJ_LOW_WORD_BUILD|PASS|bytes=%s|sha256=%s\n' \
  "$candidate_bytes" "$candidate_sha" | tee -a "$build_log"

DOOMDB_MLE_CANDIDATE="$candidate" \
DOOMDB_MLE_ORACLE="$pinned" \
  node "$project/run-javascript-candidate-parity.mjs" | tee "$parity_log"
grep -Eq "^PASS PMLE-JAVASCRIPT-CANDIDATE-PARITY tics=5250 checkpoints=5251 .*candidate_sha256=$candidate_sha oracle_sha256=$pinned_sha$" \
  "$parity_log"
printf 'PMLE_MOBJ_LOW_WORD_NODE_PARITY|PASS|candidate_sha256=%s|oracle_sha256=%s\n' \
  "$candidate_sha" "$pinned_sha" | tee -a "$parity_log"
