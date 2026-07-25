#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
tag="${PMLE_EVIDENCE_TAG:-final-2026-07-23}"
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2; exit 2; }

pinned_authority='5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
expected_authority="${PMLE_EXPECTED_AUTHORITY_SHA256:-$pinned_authority}"
expected_authority_bytes="${PMLE_EXPECTED_AUTHORITY_BYTES:-1081335}"
candidate_file="${PMLE_CANDIDATE_FILE:-}"
expected_table_pack='058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44'
expected_oracle='2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74'
pair_class='PINNED_PRODUCTION'
ledger_lock="${TMPDIR:-/tmp}/doomdb-pmle-ledger-$(id -u).lock"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doom-mle-ledger-alert.XXXXXX")"

if ! mkdir "$ledger_lock" 2>/dev/null; then
  printf 'another exhaustive ledger owns %s (owner %s)\n' "$ledger_lock" \
    "$(test -r "$ledger_lock/owner" && tr '\n' ' ' <"$ledger_lock/owner" || printf UNKNOWN)" >&2
  exit 1
fi
printf 'pid=%s\nstarted_utc=%s\n' "$$" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  >"$ledger_lock/owner"
release_ledger_lock() {
  prior_status=$?
  rm -f "$ledger_lock/owner"
  rmdir "$ledger_lock" 2>/dev/null || true
  if ! "$root/scripts/oracle-alert-window.sh" end "$alert_state" \
    LEDGER_DIFFERENTIAL; then
    prior_status=1
  fi
  rm -f "$alert_state"
  trap - EXIT
  exit "$prior_status"
}
trap release_ledger_lock EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" LEDGER_DIFFERENTIAL

if pgrep -f '[b]uild-ledger-differential.mjs' >/dev/null; then
  printf '%s\n' 'another exhaustive ledger differential is already active' >&2
  exit 1
fi
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE ledger differential requires a quiet host; active work:\n%s\n' \
    "$busy_host" >&2
  exit 1
fi

if [[ "$expected_authority" != "$pinned_authority" ]]; then
  pair_class='UNPROMOTED_CANDIDATE'
  [[ -s "$candidate_file" ]] ||
    { printf 'candidate ledger requires PMLE_CANDIDATE_FILE\n' >&2; exit 1; }
  [[ "$(wc -c <"$candidate_file" | tr -d '[:space:]')" == \
      "$expected_authority_bytes" ]] ||
    { printf 'candidate ledger byte-length mismatch\n' >&2; exit 1; }
  [[ "$(shasum -a 256 "$candidate_file" | awk '{print $1}')" == \
      "$expected_authority" ]] ||
    { printf 'candidate ledger SHA mismatch\n' >&2; exit 1; }
fi

node - "$root/versions.lock" "$pinned_authority" "$expected_oracle" <<'NODE'
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
started_epoch=$(date +%s)
started_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

{
  printf 'PMLE_LEDGER_PROVENANCE|BEGIN|executions=1|log_mode=exclusive-create|started_utc=%s|launcher_pid=%s\n' \
    "$started_utc" "$$"
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  if [[ "$pair_class" == PINNED_PRODUCTION ]]; then
    printf 'PMLE_PINNED_PAIR|authority_sha256=%s|table_sha256=%s|ojvm_jar_sha256=%s\n' \
      "$expected_authority" "$expected_table_pack" "$expected_oracle"
  else
    printf 'PMLE_CANDIDATE_PAIR|classification=%s|authority_sha256=%s|table_sha256=%s|ojvm_jar_sha256=%s\n' \
      "$pair_class" "$expected_authority" "$expected_table_pack" "$expected_oracle"
  fi
  node "$project/build-ledger-differential.mjs" --deep-every=1 --progress-every=100 |
    "$root/scripts/db_sql.sh" -
  ended_epoch=$(date +%s)
  printf 'PMLE_LEDGER_RUNTIME|elapsed_seconds=%s|ended_utc=%s\n' \
    "$((ended_epoch-started_epoch))" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1\n'
} | tee "$log"

grep -q '^PMLE_ENVIRONMENT|' "$log"
grep -q "^PMLE_ARTIFACT|source_bytes=${expected_authority_bytes}|source_sha256=${expected_authority}|table_bytes=180272|table_sha256=${expected_table_pack}$" "$log"
test "$(grep -c '^PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1|' "$log")" -eq 1
grep -q '^PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1$' "$log"
printf 'PASS PMLE-LEDGER-FINAL evidence=%s\n' "${log#$root/}"
