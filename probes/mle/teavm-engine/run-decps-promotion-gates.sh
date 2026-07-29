#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
candidate="${PMLE_CANDIDATE_FILE:-$root/artifacts/performance/pmle-decps-rank/authority-candidate-5ec18cbe4cff.js}"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
candidate_sha="${PMLE_EXPECTED_AUTHORITY_SHA256:-5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3}"
tag="${PMLE_EVIDENCE_TAG:-decps-reproducible-5ec18cbe-2026-07-25}"
modes="${PMLE_PROMOTION_MODES:-canonical coop membership}"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-gates-alert.XXXXXX")"
membership_sql="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-membership.XXXXXX.sql")"
pool_parked=0
candidate_loaded=0

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'invalid evidence tag: %s\n' "$tag" >&2
  exit 2
}
[[ -n "$modes" && "$modes" != *"  "* ]] || {
  printf 'invalid or duplicate promotion mode sequence: %s\n' "$modes" >&2
  exit 2
}
seen_modes=' '
for mode in $modes; do
  case "$mode" in
    canonical|coop|membership) ;;
    *) printf 'invalid promotion mode: %s\n' "$mode" >&2; exit 2 ;;
  esac
  case "$seen_modes" in
    *" $mode "*)
      printf 'invalid or duplicate promotion mode sequence: %s\n' "$modes" >&2
      exit 2
      ;;
  esac
  seen_modes+="$mode "
done
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] ||
  { printf 'de-CPS candidate SHA mismatch\n' >&2; exit 1; }
[[ "$(grep -Ec "c_mle_sha constant varchar2\\(64\\):='[0-9a-f]{64}';" \
  "$project/membership-recovery-differential.sql")" == 1 ]] || {
  printf 'membership source must contain exactly one strict MLE SHA binding\n' >&2
  exit 1
}
sed -E "s/(c_mle_sha constant varchar2\\(64\\):=')[0-9a-f]{64}(';)/\\1${candidate_sha}\\2/" \
  "$project/membership-recovery-differential.sql" >"$membership_sql"
grep -q "c_mle_sha constant varchar2(64):='$candidate_sha'" "$membership_sql" ||
  { printf 'membership candidate binding failed\n' >&2; exit 1; }

restore_environment() {
  local status=$?
  trap - EXIT
  if [[ "$candidate_loaded" == 1 ]]; then
    "$project/load-mle-module.sh" --production >/dev/null || status=1
  fi
  if [[ "$pool_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  "$root/scripts/oracle-alert-window.sh" end "$alert_state" DECPS_PROMOTION ||
    status=1
  rm -f "$alert_state" "$membership_sql"
  exit "$status"
}
trap restore_environment EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" DECPS_PROMOTION

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] ||
  { printf 'promotion battery requires a quiet host:\n%s\n' "$busy_host" >&2; exit 1; }
active_output="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
active="$(awk -F= '/^ACTIVE_MATCHES=/{print $2}' <<<"$active_output")"
[[ "$active" == 0 ]] ||
  { printf 'promotion battery refuses %s active match(es)\n' "$active" >&2; exit 1; }

pool_parked=1
"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
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
      slot_.job_name,true,'de-CPS promotion differential battery',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained warm pool did not park');
  end if;
end;
/
SQL

"$project/load-mle-module.sh" \
  "--javascript=$candidate" "--table-pack=$tables" >/dev/null
candidate_loaded=1

for mode in $modes; do
  if [[ "$mode" == membership ]]; then
    DOOMDB_MLE_MEMBERSHIP_SQL="$membership_sql" PMLE_EVIDENCE_TAG="$tag" \
      "$project/run-differential.sh" membership
  else
    PMLE_EVIDENCE_TAG="$tag" "$project/run-differential.sh" "$mode"
  fi
done

printf 'PASS PMLE-DECPS-PROMOTION-BATTERY candidate_sha256=%s tag=%s modes=%s\n' \
  "$candidate_sha" "$tag" "${modes// /,}"
