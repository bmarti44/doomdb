#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
tag="${PMLE_EVIDENCE_TAG:-2026-07-24}"
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'invalid evidence tag: %s\n' "$tag" >&2
  exit 2
}
evidence="$root/artifacts/performance/pmle-ledger-every-tic/component-ab-$tag"
baseline="$root/client/dist/play/doom-mle-authority-a942cd2dcbdc.js"
candidate="$root/client/dist/play/doom-mle-authority-103e15e913b3.js"
table_pack="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
ledger_lock="${TMPDIR:-/tmp}/doomdb-pmle-ledger-$(id -u).lock"
restore_needed=0

restore_production_module() {
  local status=$?
  trap - EXIT
  if [[ "$restore_needed" == 1 ]]; then
    if ! "$project/load-mle-module.sh" --production; then
      printf '%s\n' \
        'FATAL: failed to restore the production MLE module after component A/B' >&2
      exit 1
    fi
  fi
  exit "$status"
}
trap restore_production_module EXIT

[[ "${PMLE_COMPONENT_AB_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_COMPONENT_AB_EXECUTE=YES for the post-ledger diagnostic' >&2
  exit 2
}
for artifact in "$baseline" "$candidate" "$table_pack"; do test -s "$artifact";done
[[ "$(shasum -a 256 "$baseline" | awk '{print $1}')" == \
  a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2 ]]
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == \
  103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e ]]

if [[ -d "$ledger_lock" ]] ||
    pgrep -f '[b]uild-ledger-differential.mjs' >/dev/null; then
  printf '%s\n' 'exhaustive ledger differential is still active; component A/B is fenced' >&2
  exit 1
fi
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'component A/B requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}
active_output=$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)
active="$(printf '%s\n' "$active_output" |
  awk -F= '/^ACTIVE_MATCHES=/{print $2}')"
[[ "$active" == 0 ]] || {
  printf 'component A/B refuses %s active match(es)\n' "$active" >&2
  exit 1
}

mkdir -p "$evidence"
for label in a942 103e; do
  artifact="$baseline"
  [[ "$label" == 103e ]] && artifact="$candidate"
  log="$evidence/${label}.log"
  [[ ! -e "$log" ]] || { printf 'evidence exists: %s\n' "$log" >&2;exit 1; }
  restore_needed=1
  {
    printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
    "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
    "$project/load-mle-module.sh" --no-build \
      "--javascript=$artifact" "--table-pack=$table_pack"
    "$root/scripts/db_sql.sh" "$project/artifact-metadata.sql"
    node "$project/build-ledger-component-profile.mjs" \
      --limit=500 "--label=$label" | "$root/scripts/db_sql.sh" -
  } | tee "$log"
  grep -q '^PMLE_HOST_QUIESCENCE|PASS|' "$log"
  grep -q '^PMLE_ENVIRONMENT|' "$log"
  grep -q '^PMLE_ARTIFACT|' "$log"
  grep -q "^PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=${label}|tics=500|" "$log"
done
baseline_digest="$(sed -n \
  's/^PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=a942|.*|cumulative_sha256=\\([0-9a-f]\\{64\\}\\)$/\\1/p' \
  "$evidence/a942.log")"
candidate_digest="$(sed -n \
  's/^PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=103e|.*|cumulative_sha256=\\([0-9a-f]\\{64\\}\\)$/\\1/p' \
  "$evidence/103e.log")"
[[ -n "$baseline_digest" && "$baseline_digest" == "$candidate_digest" ]] || {
  printf 'component A/B canonical digest mismatch: a942=%s 103e=%s\n' \
    "${baseline_digest:-MISSING}" "${candidate_digest:-MISSING}" >&2
  exit 1
}

# Promotion updates --production to the current content-addressed authority.
# Always restore that fail-closed pin even if a later report step fails.
"$project/load-mle-module.sh" --production
restore_needed=0
printf 'PMLE_LEDGER_COMPONENT_AB|PASS|baseline=a942|candidate=103e|tics=500|canonical_sha256=%s|evidence=%s\n' \
  "$candidate_digest" "${evidence#$root/}"
