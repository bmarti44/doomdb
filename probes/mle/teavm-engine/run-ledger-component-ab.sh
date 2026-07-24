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
baseline="$root/client/dist/play/doom-mle-authority-103e15e913b3.js"
candidate="$root/client/dist/play/doom-mle-authority-e485b9418e58.js"
table_pack="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
digest_extractor="$project/extract-ledger-component-digest.sh"
ledger_lock="${TMPDIR:-/tmp}/doomdb-pmle-ledger-$(id -u).lock"
restore_needed=0
pool_restore_needed=0

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
  if [[ "$pool_restore_needed" == 1 ]]; then
    if ! "$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then
      printf '%s\n' \
        'FATAL: failed to restore the retained warm pool after component A/B' >&2
      exit 1
    fi
  fi
  exit "$status"
}
trap restore_production_module EXIT

# Extraction is proven offline before the execution opt-in, artifact loading,
# evidence-directory creation, or either scarce A/B evidence cell.
"$digest_extractor" --self-test

[[ "${PMLE_COMPONENT_AB_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_COMPONENT_AB_EXECUTE=YES for the post-ledger diagnostic' >&2
  exit 2
}
for artifact in "$baseline" "$candidate" "$table_pack"; do test -s "$artifact";done
[[ "$(shasum -a 256 "$baseline" | awk '{print $1}')" == \
  103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e ]]
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == \
  e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b ]]

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

pool_restore_needed=1
park_output=$("$root/scripts/db_sql.sh" - <<'SQL'
set serveroutput on
declare
  l_live number;
begin
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
      and assigned_match is null
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'component A/B benchmark-mode quiescence',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained warm pool did not park');
  end if;
  dbms_output.put_line('PMLE_BENCHMARK_POOL|PARKED|live_slots='||l_live);
end;
/
SQL
)
printf '%s\n' "$park_output"
grep -q '^PMLE_BENCHMARK_POOL|PARKED|live_slots=0$' <<<"$park_output"

mkdir -p "$evidence"
for label in 103e e485; do
  artifact="$baseline"
  [[ "$label" == e485 ]] && artifact="$candidate"
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
baseline_digest="$("$digest_extractor" 103e "$evidence/103e.log")"
candidate_digest="$("$digest_extractor" e485 "$evidence/e485.log")"
[[ -n "$baseline_digest" && "$baseline_digest" == "$candidate_digest" ]] || {
  printf 'component A/B canonical digest mismatch: 103e=%s e485=%s\n' \
    "${baseline_digest:-MISSING}" "${candidate_digest:-MISSING}" >&2
  exit 1
}

# Promotion updates --production to the current content-addressed authority.
# Always restore that fail-closed pin even if a later report step fails.
"$project/load-mle-module.sh" --production
restore_needed=0
printf 'PMLE_LEDGER_COMPONENT_AB|PASS|baseline=103e|candidate=e485|tics=500|canonical_sha256=%s|evidence=%s\n' \
  "$candidate_digest" "${evidence#$root/}"
