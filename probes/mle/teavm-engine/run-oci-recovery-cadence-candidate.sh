#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'OCI recovery cadence diagnostic requires %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf '%s\n' 'OCI recovery cadence diagnostic requires the DOOM schema' >&2
  exit 2
}
[[ -x "$SQL_CLIENT" ]] || {
  printf '%s\n' 'OCI recovery cadence diagnostic SQL client is unavailable' >&2
  exit 2
}

maximum="${PMLE_RECOVERY_CANDIDATE_MAX_TICS:-1024}"
[[ "$maximum" =~ ^[0-9]+$ ]] &&
  (( maximum >= 128 && maximum <= 4096 )) || {
    printf '%s\n' 'candidate checkpoint maximum must be in [128,4096]' >&2
    exit 2
  }
tag="${PMLE_RECOVERY_CANDIDATE_TAG:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
evidence="$root/artifacts/performance/pmle-worker-soak"
output="${1:-$evidence/oci-recovery-cadence-${maximum}-${tag}.log}"
[[ ! -e "$output" ]] || {
  printf 'refusing to overwrite recovery evidence: %s\n' "$output" >&2
  exit 2
}
mkdir -p "$(dirname "$output")"

worker="$root/sql/sim/084_multiplayer_worker.sql"
worker_sha="$(shasum -a 256 "$worker" | awk '{print $1}')"
candidate_sha="$(
  sed \
    -e 's/c_checkpoint_min_tics constant pls_integer:=497;/c_checkpoint_min_tics constant pls_integer:=16;/' \
    -e "s/c_checkpoint_max_tics constant pls_integer:=512;/c_checkpoint_max_tics constant pls_integer:=${maximum};/" \
    -e 's/c_checkpoint_low_awake constant pls_integer:=16;/c_checkpoint_low_awake constant pls_integer:=-1;/' \
    -e "s/c_checkpoint_recovery_diagnostic_tic constant pls_integer:=0;/c_checkpoint_recovery_diagnostic_tic constant pls_integer:=$((maximum-1));/" \
    -e 's/if p_diagnostics=1 and c_checkpoint_recovery_diagnostic_tic>0/if c_checkpoint_recovery_diagnostic_tic>0/' \
    "$worker" | shasum -a 256 | awk '{print $1}'
)"
pool_parked=0
candidate_deployed=0
safe_to_start_pool=0

sql() {
  "$root/scripts/adb-doom-sql.sh" -
}

park_pool() {
  sql <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare
  l_active number;
  l_assigned number;
  l_live number;
begin
  select count(*) into l_active from doom_match
   where match_state in('LOBBY','ACTIVE');
  select count(*) into l_assigned from doom_mle_warm_slot
   where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,
      'recovery cadence diagnostic requires idle match capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI recovery cadence diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
   where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained pool did not park');
  end if;
  dbms_output.put_line(
    'PMLE_RECOVERY_CADENCE_POOL|PASS|active=0|assigned=0|live=0');
end;
/
SQL
}

restore() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [[ "$candidate_deployed" == 1 ]]; then
    sql >>"$output" 2>&1 <<'SQL'
declare
begin
  for match_ in (
    select distinct m.match_id,m.generation from doom_match m
    join doom_match_member mm on mm.match_id=m.match_id
    where mm.player_slot=0 and mm.display_name='SOAK HOST'
  ) loop
    begin
      doom_match_worker.stop_match(match_.match_id,match_.generation);
    exception when others then null;
    end;
    delete from doom_match where match_id=match_.match_id;
  end loop;
  commit;
end;
/
SQL
    park_pool >>"$output" 2>&1
    pool_parked=1
    "$root/scripts/adb-doom-sql.sh" "$worker" >>"$output" 2>&1
    if [[ "$?" == 0 ]]; then
      candidate_deployed=0
      safe_to_start_pool=1
      printf 'PMLE_RECOVERY_CADENCE_RESTORE|PASS|worker_sha256=%s\n' \
        "$worker_sha" >>"$output"
    else
      status=1
      safe_to_start_pool=0
      printf '%s\n' \
        'PMLE_RECOVERY_CADENCE_RESTORE|FAIL|capacity=HELD_CLOSED' >>"$output"
    fi
  fi
  if [[ "$pool_parked" == 1 && "$safe_to_start_pool" == 1 ]]; then
    sql >>"$output" 2>&1 <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    [[ "$?" == 0 ]] || status=1
  fi
  unset ADB_PASSWORD
  exit "$status"
}
trap restore EXIT HUP INT TERM

{
  printf 'PMLE_RECOVERY_CADENCE_PREDECLARATION|DIAGNOSTIC_NOT_GATE'
  printf '|venue=OCI_ALWAYS_FREE_26AI|checkpoint_max_tics=%s' "$maximum"
  printf '|checkpoint_min_tics=16|checkpoint_low_awake=-1'
  printf '|kill_window=%s-%s' "$((maximum-15))" "$((maximum-1))"
  printf '|committed_frontier_pause_tic=%s|pause_seconds=135' "$((maximum-1))"
  printf '|busy_lease_renewals=3'
  printf '|candidate_pause_activation=UNCONDITIONAL'
  printf '|phase_budget_ms=45000|detection_budget_ms=15000'
  printf '|production_cadence_unchanged=497-512'
  printf '|worker_source_sha256=%s|candidate_source_sha256=%s\n' \
    "$worker_sha" "$candidate_sha"
} | tee "$output"

park_pool 2>&1 | tee -a "$output"
pool_parked=1
safe_to_start_pool=1

candidate_deployed=1
sed \
  -e 's/c_checkpoint_min_tics constant pls_integer:=497;/c_checkpoint_min_tics constant pls_integer:=16;/' \
  -e "s/c_checkpoint_max_tics constant pls_integer:=512;/c_checkpoint_max_tics constant pls_integer:=${maximum};/" \
  -e 's/c_checkpoint_low_awake constant pls_integer:=16;/c_checkpoint_low_awake constant pls_integer:=-1;/' \
  -e "s/c_checkpoint_recovery_diagnostic_tic constant pls_integer:=0;/c_checkpoint_recovery_diagnostic_tic constant pls_integer:=$((maximum-1));/" \
  -e 's/if p_diagnostics=1 and c_checkpoint_recovery_diagnostic_tic>0/if c_checkpoint_recovery_diagnostic_tic>0/' \
  "$worker" | sql >>"$output" 2>&1

sql >>"$output" 2>&1 <<SQL
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_errors number;
begin
  select count(*) into l_errors from user_errors
   where name='DOOM_MATCH_WORKER';
  if l_errors<>0 then
    raise_application_error(-20796,'candidate worker has compilation errors');
  end if;
  doom_match_worker.start_warm_pool;
  dbms_output.put_line(
    'PMLE_RECOVERY_CADENCE_DEPLOY|PASS|candidate_sha256=$candidate_sha');
end;
/
SQL
pool_parked=0

DOOMDB_PLAY_BASE_URL="${T112_HOSTED_INDEX_URL:-https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/app/}" \
DOOMDB_PLAY_PATH=multiplayer.html \
DOOMDB_SOAK_HEALTH_URL="${ADB_ORDS_HEALTH_URL:-https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/public_health/}" \
DOOMDB_DB_SQL_CLIENT="$root/scripts/adb-doom-sql.sh" \
DOOMDB_MANAGED_ADB=1 \
DOOMDB_MULTIPLAYER_SOAK_SECONDS=20 \
DOOMDB_MULTIPLAYER_STARTUP_TIMEOUT_MS=600000 \
DOOMDB_MULTIPLAYER_PROGRESS_TIMEOUT_MS=600000 \
DOOMDB_ROUTE_DIAGNOSTICS=1 \
DOOMDB_HIGH_AWAKE_RECOVERY_DIAGNOSTIC=1 \
DOOMDB_HIGH_AWAKE_RECOVERY_MAX_TICS="$maximum" \
  bash "$root/tests/verify-p13.5-multiplayer-soak.sh" 2>&1 |
  tee -a "$output"

grep -Fq "PMLE_HIGH_AWAKE_RECOVERY|DIAGNOSTIC_NOT_GATE|" "$output"
grep -Fq "|checkpoint_max_tics=$maximum|" "$output"
printf 'PMLE_RECOVERY_CADENCE_DIAGNOSTIC|PASS|checkpoint_max_tics=%s\n' \
  "$maximum" | tee -a "$output"
