#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
tag="${PMLE_EVIDENCE_TAG:-final-2026-07-23}"
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2; exit 2; }

expected_authority='a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2'
expected_table_pack='058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44'
expected_oracle='2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74'

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE ledger differential requires a quiet host; active work:\n%s\n' \
    "$busy_host" >&2
  exit 1
fi

node - "$root/versions.lock" "$expected_authority" "$expected_oracle" <<'NODE'
import fs from 'node:fs';
const [path, authority, oracle] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(path, 'utf8'));
if (lock.teaVM.outputSha256 !== authority) {
  throw new Error(`authority pin mismatch: ${lock.teaVM.outputSha256}`);
}
if (lock.teaVM.canonicalOracleJarSha256 !== oracle) {
  throw new Error(`OJVM oracle pin mismatch: ${lock.teaVM.canonicalOracleJarSha256}`);
}
NODE

evidence="$root/artifacts/performance/pmle-ledger-every-tic"
mkdir -p "$evidence"
log="$evidence/run-${tag}.log"
[[ ! -e "$log" ]] ||
  { printf 'ledger evidence already exists: %s\n' "$log" >&2; exit 1; }

{
  printf 'PMLE_LEDGER_PROVENANCE|BEGIN|executions=1|log_mode=exclusive-create\n'
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_PINNED_PAIR|authority_sha256=%s|table_sha256=%s|ojvm_jar_sha256=%s\n' \
    "$expected_authority" "$expected_table_pack" "$expected_oracle"
  node "$project/build-ledger-differential.mjs" --deep-every=1 |
    "$root/scripts/db_sql.sh" -
  printf 'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1\n'
} | tee "$log"

grep -q '^PMLE_ENVIRONMENT|' "$log"
grep -q "^PMLE_ARTIFACT|source_bytes=1167197|source_sha256=${expected_authority}|table_bytes=180272|table_sha256=${expected_table_pack}$" "$log"
test "$(grep -c '^PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1|' "$log")" -eq 1
grep -q '^PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1$' "$log"
printf 'PASS PMLE-LEDGER-FINAL evidence=%s\n' "${log#$root/}"
