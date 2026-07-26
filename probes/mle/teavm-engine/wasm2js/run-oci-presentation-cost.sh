#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spike/../../../.." && pwd)"
artifact="$spike/target/wasm/doom-wasm2js-presentation.o0.bundle.mjs"
evidence="$root/artifacts/performance/pmle-database-frames"
tag="${PMLE_WASM2JS_COST_TAG:-wasm2js-presentation-cost-v1-2026-07-26}"
pool_log="$evidence/oci-$tag-pool.log"
install_log="$evidence/oci-$tag-install.log"
rank_log="$evidence/oci-$tag-rank.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_WASM2JS_COST_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_WASM2JS_COST_EXECUTE=YES to run the OCI cost cell' >&2
  exit 2
}
[[ "$tag" =~ ^[a-z0-9][a-z0-9-]{2,80}$ ]] || {
  printf 'invalid presentation-cost tag: %s\n' "$tag" >&2; exit 2; }
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
    SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI cost authority is absent: %s\n' "$name" >&2; exit 2; }
done
[[ "$ADB_USERNAME" == DOOM ]]
for input in "$artifact" "$spike/install-presentation-cost.sh" \
    "$spike/install-presentation-cost-jdbc.sh" \
    "$spike/benchmark-presentation-cost.sql" \
    "$spike/cleanup-presentation-cost.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'OCI presentation-cost input unavailable: %s\n' "$input" >&2
    exit 2
  }
done
mkdir -p "$evidence"
for output in "$pool_log" "$install_log" "$rank_log" "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'OCI presentation-cost evidence exists: %s\n' "$output" >&2
    exit 1
  }
done

competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[r]un-oci-dvr-compression|[r]un-oci-raw-frame|[r]un-oci-presentation-decps-rank|[r]un-oci-mle-rank/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'OCI presentation-cost cell refuses competing OCI work:\n%s\n' \
    "$competing" >&2; exit 1; }

pool_parked=0
diagnostic_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" \
        "$spike/cleanup-presentation-cost.sql" >"$cleanup_log"; then
      safe=0
    fi
  else
    : >"$cleanup_log"
  fi
  if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_objects number;l_sha varchar2(64);
begin
  select count(*) into l_objects from user_objects
    where object_name like 'DOOM_WASM2JS_COST%';
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
      l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' then
    raise_application_error(-20796,'presentation-cost postflight failed');
  end if;
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_POSTFLIGHT|PASS|diagnostic_objects=0|production_sha256='||
    l_sha);
end;
/
SQL
  then safe=0; fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$safe" != 1 ]]; then
    printf '%s\n' \
      'PMLE_WASM2JS_COST_CAPACITY|HELD_CLOSED|reason=cleanup_unproven' >&2
    status=1
  fi
  exit "$status"
}
trap finish EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$pool_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'presentation-cost cell requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI wasm2js presentation cost',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fqx \
  'PMLE_WASM2JS_COST_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0' \
  "$pool_log"

diagnostic_loaded=1
"$spike/install-presentation-cost-jdbc.sh" "$artifact" | tee "$install_log"
grep -Eq '^PMLE_WASM2JS_COST_FIRST_CALL\|PASS\|' "$install_log"

{
  printf '%s\n' \
    "begin dbms_session.set_identifier('OCI_WASM2JS_PRESENTATION_COST');end;" /
  cat "$spike/benchmark-presentation-cost.sql"
} | "$root/scripts/adb-doom-sql.sh" - | tee "$rank_log"
grep -Eq \
  '^PMLE_WASM2JS_COST_VERDICT\|(UNIFIED_LIVE_COST_ELIGIBLE_FOR_PARITY_WORK|SPLIT_RENDER_COST_ELIGIBLE_FOR_PARITY_WORK|DVR_ONLY_ON_COST)\|' \
  "$rank_log"

printf 'PASS PMLE-WASM2JS-PRESENTATION-COST artifact_sha256=%s rank_log=%s\n' \
  "$(shasum -a 256 "$artifact" | awk '{print $1}')" \
  "${rank_log#"$root"/}"
