#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
candidate="$root/client/dist/play/doom-mle-authority-5ec18cbe4cff.js"
rollback="$root/client/dist/play/doom-mle-authority-e485b9418e58.js"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
candidate_sha=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3
candidate_bytes=1081335
rollback_sha=e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b
table_sha=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44
tag="${PMLE_EVIDENCE_TAG:-decps-reproducible-5ec18cbe-2026-07-25}"
evidence="$root/artifacts/performance/pmle-decps-rank"
log="$evidence/deploy-${tag}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-deploy-alert.XXXXXX")"
state_updater="$root/scripts/set-decps-deployment-state.mjs"
pool_parked=0
deployment_started=0
alert_started=0
alert_validation_failed=0
alert_label=DECPS_DEPLOY
rollback_permitted=1

[[ "${PMLE_DECPS_DEPLOY:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_DECPS_DEPLOY=YES to deploy the promoted authority' >&2
  exit 2
}
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2; exit 2; }
[[ ! -e "$log" ]] || { printf 'deployment evidence exists: %s\n' "$log" >&2; exit 1; }

for tuple in \
    "$candidate|$candidate_bytes|$candidate_sha" \
    "$rollback|1171896|$rollback_sha" \
    "$tables|180272|$table_sha"; do
  IFS='|' read -r path expected_bytes expected_sha <<<"$tuple"
  [[ -s "$path" ]] || { printf 'deployment artifact missing: %s\n' "$path" >&2; exit 1; }
  actual_bytes="$(wc -c <"$path" | tr -d '[:space:]')"
  actual_sha="$(shasum -a 256 "$path" | awk '{print $1}')"
  [[ "$actual_bytes" == "$expected_bytes" && "$actual_sha" == "$expected_sha" ]] || {
    printf 'deployment artifact drift: %s actual=%s/%s expected=%s/%s\n' \
      "$path" "$actual_bytes" "$actual_sha" "$expected_bytes" "$expected_sha" >&2
    exit 1
  }
done

node - "$root/versions.lock" "$candidate_sha" "$candidate_bytes" <<'NODE'
import fs from 'node:fs';
const [lockPath, expectedSha, expectedBytes] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
if (lock.teaVM.outputSha256 !== expectedSha
    || lock.teaVM.outputBytes !== Number(expectedBytes)
    || !Array.isArray(lock.teaVM.authorityExtraPatches)
    || !/^[0-9a-f]{64}$/.test(
      lock.teaVM.authorityExtraPatchSetSha256 ?? '')) {
  throw new Error('versions.lock is not the promoted de-CPS provenance set');
}
NODE

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-differential[.]sh|[r]un-worker-cutover|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'de-CPS deployment refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'de-CPS deployment requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}

active="$("$root/scripts/db_sql.sh" - <<'SQL' |
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state in('LOBBY','ACTIVE')
  and expires_at>(localtimestamp at time zone 'UTC');
SQL
  awk -F= '/^ACTIVE_MATCHES=/{print $2}'
)"
[[ "$active" == 0 ]] ||
  { printf 'de-CPS deployment refuses %s active match(es)\n' "$active" >&2; exit 1; }

start_pool() {
  "$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
}

park_pool() {
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
      slot_.job_name,true,'de-CPS production deployment',
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
}

install_worker_contract() {
  local authority_sha="$1"
  if [[ "$authority_sha" == "$candidate_sha" ]]; then
    "$root/scripts/db_sql.sh" "$root/sql/sim/088_mle_match_runtime.sql"
  elif [[ "$authority_sha" == "$rollback_sha" ]]; then
    sed "s/$candidate_sha/$rollback_sha/g" \
      "$root/sql/sim/088_mle_match_runtime.sql" |
      "$root/scripts/db_sql.sh" -
  else
    printf 'unsupported worker-contract authority SHA: %s\n' \
      "$authority_sha" >&2
    return 1
  fi
}

verify_deployed_contract() {
  local authority_sha="$1"
  local authority_bytes="$2"
  local marker="$3"
  "$root/scripts/db_sql.sh" "$project/artifact-metadata.sql" >>"$log"
  grep -Fqx \
    "PMLE_ARTIFACT|source_bytes=$authority_bytes|source_sha256=$authority_sha|table_bytes=180272|table_sha256=$table_sha" \
    "$log"
  "$root/scripts/db_sql.sh" - >>"$log" <<SQL
set heading off feedback off pagesize 0 linesize 32767 trimspool on
select '$marker|PASS|sha256=$authority_sha'
from dual
where (select count(*) from user_source
       where name='DOOM_MLE_MATCH_RUNTIME' and type='PACKAGE BODY'
         and text like '%$authority_sha%')=1
  and (select count(*) from user_objects
       where object_name='DOOM_MLE_MATCH_RUNTIME'
         and object_type='PACKAGE BODY' and status='VALID')=1;
SQL
  grep -Fqx "$marker|PASS|sha256=$authority_sha" "$log"
}

finish() {
  local status=$?
  local safe_to_start_pool=1
  local capacity_hold_proven=1
  local intervention_reason=
  trap - EXIT
  if [[ "$alert_validation_failed" == 1 ]]; then
    safe_to_start_pool=0
    intervention_reason=deployment_alert_window_failed
  fi
  # Any failing start_pool call may have created only part of the pool, and
  # the final deployment marker is deliberately after a successful restart.
  # Never trust the shell's pool_parked bookkeeping on a failure path: always
  # re-park and prove the pool empty before replacing its imported MLE module.
  # An unparkable pool is an intervention-required state, not permission to
  # attempt a risky rollback.
  if [[ "$status" != 0 && "$deployment_started" == 1 ]]; then
    if park_pool >>"$log" 2>&1; then
      pool_parked=1
      printf '%s\n' \
        'PMLE_DECPS_DEPLOY_ROLLBACK_POOL|PASS|live_slots=0' |
        tee -a "$log" >&2
    else
      rollback_permitted=0
      safe_to_start_pool=0
      capacity_hold_proven=0
      pool_parked=0
      intervention_reason=rollback_pool_park_failed
      printf '%s\n' \
        'PMLE_DECPS_DEPLOY_ROLLBACK_POOL|FAIL|reason=park_unproven' |
        tee -a "$log" >&2
    fi
  fi
  # If the initial window already closed before a later source/dashboard
  # failure, open a dedicated rollback window. A rollback without its own
  # Oracle incident scan is not verified and cannot reopen capacity.
  if [[ "$status" != 0 && "$deployment_started" == 1 &&
        "$rollback_permitted" == 1 && "$alert_started" == 0 ]]; then
    if "$root/scripts/oracle-alert-window.sh" begin \
        "$alert_state" DECPS_DEPLOY_ROLLBACK >>"$log" 2>&1; then
      alert_started=1
      alert_label=DECPS_DEPLOY_ROLLBACK
    else
      safe_to_start_pool=0
      [[ -n "$intervention_reason" ]] ||
        intervention_reason=rollback_alert_window_unavailable
    fi
  fi
  if [[ "$status" != 0 && "$deployment_started" == 1 &&
        "$rollback_permitted" == 1 ]]; then
    printf 'PMLE_DECPS_DEPLOY_ROLLBACK|BEGIN|sha256=%s\n' "$rollback_sha" |
      tee -a "$log" >&2
    if "$project/load-mle-module.sh" \
        "--javascript=$rollback" "--table-pack=$tables" >>"$log" 2>&1; then
      if DOOMDB_TIC0_AUTHORITY="$rollback" \
          "$project/load-tic0-checkpoint-bank.sh" >>"$log" 2>&1; then
        if install_worker_contract "$rollback_sha" >>"$log" 2>&1; then
          if verify_deployed_contract \
              "$rollback_sha" 1171896 \
              PMLE_DECPS_ROLLBACK_WORKER_CONTRACT; then
            printf 'PMLE_DECPS_DEPLOY_ROLLBACK|PASS|sha256=%s\n' \
              "$rollback_sha" | tee -a "$log" >&2
          else
            printf 'PMLE_DECPS_DEPLOY_ROLLBACK|FAIL|phase=verification|sha256=%s\n' \
              "$rollback_sha" | tee -a "$log" >&2
            status=1
            safe_to_start_pool=0
          fi
        else
          printf 'PMLE_DECPS_DEPLOY_ROLLBACK|FAIL|phase=worker_contract|sha256=%s\n' \
            "$rollback_sha" | tee -a "$log" >&2
          status=1
          safe_to_start_pool=0
        fi
      else
        printf 'PMLE_DECPS_DEPLOY_ROLLBACK|FAIL|phase=checkpoint_bank|sha256=%s\n' \
          "$rollback_sha" | tee -a "$log" >&2
        status=1
        safe_to_start_pool=0
      fi
    else
      printf 'PMLE_DECPS_DEPLOY_ROLLBACK|FAIL|phase=module|sha256=%s\n' \
        "$rollback_sha" | tee -a "$log" >&2
      status=1
      safe_to_start_pool=0
    fi
  fi
  if [[ "$safe_to_start_pool" == 0 ]]; then
    [[ -n "$intervention_reason" ]] ||
      intervention_reason=rollback_unproven
  fi
  if [[ "$alert_started" == 1 ]]; then
    if "$root/scripts/oracle-alert-window.sh" end \
        "$alert_state" "$alert_label" | tee -a "$log"; then
      alert_started=0
    else
      alert_started=0
      status=1
      safe_to_start_pool=0
      [[ -n "$intervention_reason" ]] ||
        intervention_reason=deployment_alert_window_failed
    fi
  fi
  if [[ "$status" != 0 && "$deployment_started" == 1 ]]; then
    if [[ "$safe_to_start_pool" == 1 ]]; then
      state=SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING
    elif [[ "$capacity_hold_proven" == 1 ]]; then
      printf 'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=%s\n' \
        "$intervention_reason" | tee -a "$log" >&2
      state=INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED
    else
      printf 'PMLE_DECPS_DEPLOY_CAPACITY|UNPROVEN|reason=%s\n' \
        "$intervention_reason" | tee -a "$log" >&2
      state=INTERVENTION_REQUIRED_CAPACITY_UNPROVEN
    fi
    if node "$state_updater" --state "$state" \
        --evidence "${log#"$root"/}" >>"$log" 2>&1 &&
        node "$root/scripts/build-mle-dashboard-status.mjs" >>"$log" 2>&1; then
      printf 'PMLE_DECPS_DEPLOY_DASHBOARD_ROLLBACK|PASS|state=%s\n' \
        "$state" | tee -a "$log" >&2
    else
      printf 'PMLE_DECPS_DEPLOY_DASHBOARD_ROLLBACK|FAIL|state=%s\n' \
        "$state" | tee -a "$log" >&2
      status=1
      safe_to_start_pool=0
      intervention_reason=dashboard_state_update_failed
      if [[ "$capacity_hold_proven" == 1 ]]; then
        state=INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED
        printf 'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=%s\n' \
          "$intervention_reason" | tee -a "$log" >&2
      else
        state=INTERVENTION_REQUIRED_CAPACITY_UNPROVEN
        printf 'PMLE_DECPS_DEPLOY_CAPACITY|UNPROVEN|reason=%s\n' \
          "$intervention_reason" | tee -a "$log" >&2
      fi
      if node "$state_updater" \
          --state "$state" \
          --evidence "${log#"$root"/}" >>"$log" 2>&1 &&
          node "$root/scripts/build-mle-dashboard-status.mjs" \
            >>"$log" 2>&1; then
        printf 'PMLE_DECPS_DEPLOY_DASHBOARD_INTERVENTION_RETRY|PASS|state=%s\n' \
          "$state" | tee -a "$log" >&2
      else
        printf 'PMLE_DECPS_DEPLOY_DASHBOARD_INTERVENTION_RETRY|FAIL|state=%s\n' \
          "$state" | tee -a "$log" >&2
      fi
    fi
  fi
  if [[ "$pool_parked" == 1 && "$safe_to_start_pool" == 1 ]]; then
    if start_pool; then
      pool_parked=0
    else
      status=1
      safe_to_start_pool=0
      if park_pool >>"$log" 2>&1; then
        pool_parked=1
        intervention_reason=capacity_restart_failed
        state=INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED
        printf '%s\n' \
          'PMLE_DECPS_DEPLOY_RESTART_REPARK|PASS|live_slots=0' |
          tee -a "$log" >&2
        printf 'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=%s\n' \
          "$intervention_reason" | tee -a "$log" >&2
      else
        pool_parked=0
        capacity_hold_proven=0
        intervention_reason=capacity_restart_repark_failed
        state=INTERVENTION_REQUIRED_CAPACITY_UNPROVEN
        printf '%s\n' \
          'PMLE_DECPS_DEPLOY_RESTART_REPARK|FAIL|reason=park_unproven' |
          tee -a "$log" >&2
        printf 'PMLE_DECPS_DEPLOY_CAPACITY|UNPROVEN|reason=%s\n' \
          "$intervention_reason" | tee -a "$log" >&2
      fi
      if node "$state_updater" \
          --state "$state" \
          --evidence "${log#"$root"/}" >>"$log" 2>&1 &&
          node "$root/scripts/build-mle-dashboard-status.mjs" \
            >>"$log" 2>&1; then
        printf 'PMLE_DECPS_DEPLOY_DASHBOARD_RESTART_FAILURE|PASS|state=%s\n' \
          "$state" | tee -a "$log" >&2
      else
        printf 'PMLE_DECPS_DEPLOY_DASHBOARD_RESTART_FAILURE|FAIL|state=%s\n' \
          "$state" | tee -a "$log" >&2
      fi
    fi
  elif [[ "$pool_parked" == 1 && "$capacity_hold_proven" == 1 ]] &&
      ! grep -Eq \
        '^PMLE_DECPS_DEPLOY_CAPACITY\|HELD_CLOSED\|reason=' "$log"; then
    printf 'PMLE_DECPS_DEPLOY_CAPACITY|HELD_CLOSED|reason=%s\n' \
      "${intervention_reason:-deployment_validation_failed}" |
      tee -a "$log" >&2
  fi
  exit "$status"
}
trap finish EXIT

"$root/scripts/oracle-alert-window.sh" begin "$alert_state" DECPS_DEPLOY
alert_started=1
mkdir -p "$evidence"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
} | tee "$log"

pool_parked=1
park_pool >>"$log"

deployment_started=1
"$project/load-mle-module.sh" --production | tee -a "$log"
DOOMDB_TIC0_AUTHORITY="$candidate" \
DOOMDB_TIC0_EXPECT_EQUIVALENT_AUTHORITY_SHA="$rollback_sha" \
  "$project/load-tic0-checkpoint-bank.sh" | tee -a "$log"
grep -Fqx "PMLE_TIC0_BANK_EQUIVALENCE|PASS|entries=10|from_authority_sha256=$rollback_sha|to_authority_sha256=$candidate_sha" \
  "$log"
install_worker_contract "$candidate_sha" | tee -a "$log"
verify_deployed_contract \
  "$candidate_sha" "$candidate_bytes" PMLE_DECPS_WORKER_CONTRACT
printf 'PMLE_DECPS_DEPLOY_DATABASE|READY|sha256=%s\n' "$candidate_sha" |
  tee -a "$log"

node "$state_updater" \
  --state DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING \
  --evidence "${log#"$root"/}" | tee -a "$log"
node "$root/scripts/build-mle-dashboard-status.mjs" | tee -a "$log"
node "$root/tests/verify-mle-dashboard.mjs" | tee -a "$log"
if "$root/scripts/oracle-alert-window.sh" end \
    "$alert_state" DECPS_DEPLOY | tee -a "$log"; then
  alert_started=0
else
  alert_started=0
  alert_validation_failed=1
  printf '%s\n' 'de-CPS deployment alert window failed' >&2
  exit 1
fi
start_pool
pool_parked=0
printf 'PMLE_DECPS_DEPLOY|PASS|bytes=%s|sha256=%s|rollback_sha256=%s\n' \
  "$candidate_bytes" "$candidate_sha" "$rollback_sha" | tee -a "$log"
