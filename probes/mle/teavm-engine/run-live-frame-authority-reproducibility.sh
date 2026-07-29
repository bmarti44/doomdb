#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-live-frame-authority"
candidate="$evidence/authority-candidate-c613bb5106d6.js"
preserved_input="$evidence/input-bytecode-b80f697e8a49.jar"
preserved_mocha="$evidence/mocha-bytecode-42b25147133b.jar"
patch="$project/0006-teavm-authority-no-blocking-wait.patch"
extractor="$project/extract-build-sha.mjs"
ledger_auditor="$project/compare-ledger-progress.mjs"
ledger="$root/artifacts/performance/pmle-ledger-every-tic/run-live-frame-c613-2026-07-28.log"
ledger_baseline_5ec="$root/artifacts/performance/pmle-ledger-every-tic/run-decps-reproducible-5ec18cbe-2026-07-25.log"
ledger_baseline_2848="$root/artifacts/performance/pmle-ledger-every-tic/run-decps-2848ef7a-2026-07-24.log"
ledger_terminal_sha=089ba1518faf0e62be1c59d09e576c00e75c1845c00c3d45e497f7e3b7048584
log="${PMLE_LIVE_FRAME_REPRODUCIBILITY_LOG:-$evidence/rebuild-c613-with-production-patch.log}"

IFS=$'\t' read -r expected_bytes expected_sha expected_input expected_mocha \
  candidate_patch_set production_patch_set expected_table_bytes \
  expected_table expected_ojvm < <(
  node - "$root/versions.lock" <<'NODE'
import fs from 'node:fs';
const lock=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const live=lock.teaVM?.liveFrameRenderer;
if(!live)throw new Error('live-frame candidate pin is absent');
process.stdout.write([
  live.authorityCandidateBytes,
  live.authorityCandidateSha256,
  live.authorityCandidateInputBytecodeSha256,
  live.authorityCandidateMochaBytecodeSha256,
  live.authorityCandidatePatchSetSha256,
  lock.teaVM.authorityExtraPatchSetSha256,
  lock.teaVM.canonicalTablePackBytes,
  lock.teaVM.canonicalTablePackSha256,
  lock.teaVM.canonicalOracleJarSha256,
].join('\t')+'\n');
NODE
)

[[ "${PMLE_LIVE_FRAME_REPRODUCIBILITY:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_LIVE_FRAME_REPRODUCIBILITY=YES after the c613 ledger passes' >&2
  exit 2
}
[[ "$expected_bytes" == 1181281
   && "$expected_sha" == \
      c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1
   && "$expected_input" == \
      b80f697e8a49775c4b98db6b5ce47df46aee99398b22227a8408585c103ceaa4
   && "$expected_mocha" == \
      42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e
   && "$candidate_patch_set" == none ]]
[[ ! -e "$log" ]] || {
  printf 'live-frame reproducibility evidence exists: %s\n' "$log" >&2
  exit 1
}
for file in "$candidate" "$preserved_input" "$preserved_mocha" \
  "$patch" "$extractor" "$ledger_auditor" "$ledger" \
  "$ledger_baseline_5ec" "$ledger_baseline_2848"; do
  [[ -s "$file" && ! -L "$file" ]] || {
    printf 'live-frame reproducibility input missing: %s\n' "$file" >&2
    exit 2
  }
done
file_identity() {
  local file="$1" bytes="$2" digest="$3"
  [[ "$(wc -c <"$file" | tr -d '[:space:]')" == "$bytes"
     && "$(shasum -a 256 "$file" | awk '{print $1}')" == "$digest" ]]
}
file_identity "$candidate" "$expected_bytes" "$expected_sha"
[[ "$(shasum -a 256 "$preserved_input" | awk '{print $1}')" == \
  "$expected_input" ]]
[[ "$(shasum -a 256 "$preserved_mocha" | awk '{print $1}')" == \
  "$expected_mocha" ]]
computed_patch_set="$(
  printf '%s  %s\n' \
    "$(shasum -a 256 "$patch" | awk '{print $1}')" "$(basename "$patch")" |
  shasum -a 256 | awk '{print $1}'
)"
[[ "$computed_patch_set" == "$production_patch_set" ]]
node "$extractor" --self-test
node "$ledger_auditor" --self-test
ledger_audit="$(
  node "$ledger_auditor" "$ledger" "$ledger_baseline_5ec" \
    "$ledger_baseline_2848"
)"
expected_ledger_audit="PMLE_LEDGER_PROGRESS_AUDIT|PASS|classification=TERMINAL|markers=133|through_tic=13272|progress_sha256=$ledger_terminal_sha|baselines=2|terminal_sha256=$ledger_terminal_sha"
[[ "$ledger_audit" == "$expected_ledger_audit" ]] || {
  printf 'live-frame authority ledger is not terminal and accepted: %s\n' \
    "$ledger_audit" >&2
  exit 1
}
printf '%s\n' "$ledger_audit"
candidate_pair="PMLE_CANDIDATE_PAIR|classification=UNPROMOTED_CANDIDATE|authority_sha256=$expected_sha|table_sha256=$expected_table|ojvm_jar_sha256=$expected_ojvm"
artifact_pair="PMLE_ARTIFACT|source_bytes=$expected_bytes|source_sha256=$expected_sha|table_bytes=$expected_table_bytes|table_sha256=$expected_table"
[[ "$(grep -Fxc "$candidate_pair" "$ledger")" == 1
   && "$(grep -Fxc "$artifact_pair" "$ledger")" == 1
   && "$(grep -Fxc \
      'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1' \
      "$ledger")" == 1 ]] || {
  printf '%s\n' 'live-frame ledger provenance tuple is missing or ambiguous' >&2
  exit 1
}

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[r]un-worker-soak|[r]un-live-command-matrix-mle|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'live-frame rebuild refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'live-frame rebuild requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}

PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
PMLE_AUTHORITY_CANDIDATE_REASON=live-frame-promotion-rebuild \
DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch" \
  "$project/build-simulation.sh" 2>&1 | tee "$log"

rebuilt="$project/target/javascript/doom-mle-simulation-engine-headless.js"
rebuilt_input="$project/target/mochadoom-mle-engine-slice-1.0.0.jar"
rebuilt_mocha="$project/target/mochadoom-mle-simulation.jar"
file_identity "$rebuilt" "$expected_bytes" "$expected_sha" || {
  printf 'patched live-frame rebuild drifted from c613\n' >&2
  exit 1
}
cmp -s "$candidate" "$rebuilt"
[[ "$(shasum -a 256 "$rebuilt_input" | awk '{print $1}')" == \
  "$expected_input" ]]
rebuilt_mocha_sha="$(shasum -a 256 "$rebuilt_mocha" | awk '{print $1}')"

marker='PASS PMLE-TEAVM-SIMULATION-BUILD'
[[ "$(node "$extractor" "$log" "$marker" sha256)" == "$expected_sha" ]]
[[ "$(node "$extractor" "$log" "$marker" input_bytecode_sha256)" == \
  "$expected_input" ]]
[[ "$(node "$extractor" "$log" "$marker" mocha_bytecode_sha256)" == \
  "$rebuilt_mocha_sha" ]]
[[ "$(node "$extractor" "$log" "$marker" classification token)" == \
  UNPROMOTED_CANDIDATE ]]
[[ "$(node "$extractor" "$log" "$marker" candidate_reason token)" == \
  live-frame-promotion-rebuild ]]
[[ "$(node "$extractor" "$log" "$marker" patch_set_sha256)" == \
  "$production_patch_set" ]]

printf 'PMLE_LIVE_FRAME_REPRODUCIBILITY|PASS|bytes=%s|sha256=%s|input_bytecode_sha256=%s|candidate_mocha_sha256=%s|patched_mocha_sha256=%s|candidate_patch_set=none|production_patch_set_sha256=%s|ledger_terminal_sha256=%s\n' \
  "$expected_bytes" "$expected_sha" "$expected_input" "$expected_mocha" \
  "$rebuilt_mocha_sha" "$production_patch_set" "$ledger_terminal_sha" |
  tee -a "$log"
